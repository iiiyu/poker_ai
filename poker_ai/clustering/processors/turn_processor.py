"""Turn stage processor with aggressive memory management."""

import numpy as np
from typing import List

from .base_processor import BaseProcessor
from ..game_utility import GameUtility


class TurnProcessor(BaseProcessor):
    """Processes turn combinations with memory-safe streaming."""
    
    def __init__(self, 
                 storage, 
                 memory_manager,
                 n_clusters: int,
                 n_simulations: int = 100,
                 batch_size: int = 50):
        """
        Initialize turn processor.
        
        Args:
            storage: Storage backend instance
            memory_manager: Memory manager instance
            n_clusters: Number of turn clusters
            n_simulations: Number of river simulations per turn
            batch_size: Processing batch size
        """
        super().__init__(storage, memory_manager, n_clusters, batch_size)
        self.n_simulations = n_simulations
        
        # Cards setup
        self.suits = [1, 2, 3, 4]
        self.ranks = list(range(2, 15))  # 2-14 (Ace high)
        self._cards = np.array([[rank, suit] for suit in self.suits 
                                for rank in self.ranks])
    
    def compute_distribution(self, combo: np.ndarray) -> np.ndarray:
        """
        Compute turn distribution for a single combination.
        
        This is the memory-critical operation that generates distributions
        based on river card simulations.
        
        Args:
            combo: Turn combination (hand + flop + turn cards)
            
        Returns:
            Turn distribution array
        """
        # Extract cards
        our_hand = combo[:2]
        board = combo[2:6]  # flop + turn
        
        # Get available river cards
        unavailable = combo
        available_cards = self.get_available_cards(unavailable)
        
        # Sample river cards and compute EHS distribution
        distribution = self.simulate_turn_ehs_distribution(
            available_cards, board, our_hand
        )
        
        return distribution
    
    def _calculate_ehs(self, our_hand: np.ndarray, board: np.ndarray,
                       available_cards: np.ndarray) -> float:
        """
        Calculate Expected Hand Strength.
        
        Args:
            our_hand: Player's hole cards
            board: Board cards
            available_cards: Cards available for opponent
            
        Returns:
            EHS value (win probability)
        """
        wins = 0
        total = min(self.n_simulations, len(available_cards) * (len(available_cards) - 1) // 2)
        
        for _ in range(total):
            # Sample opponent hand
            opp_indices = np.random.choice(len(available_cards), 2, replace=False)
            opp_cards = available_cards[opp_indices]
            
            # Create game state
            game = GameUtility(our_hand=our_hand, board=board, cards=self._cards)
            game.opp_hand = opp_cards
            
            winner = game.get_winner()
            if winner == 0:  # We win
                wins += 1
            elif winner == 2:  # Tie
                wins += 0.5
        
        return wins / total if total > 0 else 0.5
    
    def get_available_cards(self, unavailable_cards: np.ndarray) -> np.ndarray:
        """Get cards that are still available (not in hand or on board)."""
        # Create mask for unavailable cards
        mask = np.ones(len(self._cards), dtype=bool)
        
        for card in unavailable_cards:
            # Find matching card in deck
            matches = (self._cards[:, 0] == card[0]) & (self._cards[:, 1] == card[1])
            mask &= ~matches
        
        return self._cards[mask]
    
    def simulate_turn_ehs_distribution(self, 
                                      available_cards: np.ndarray,
                                      board: np.ndarray,
                                      our_hand: np.ndarray) -> np.ndarray:
        """
        Simulate river cards to compute turn EHS distribution.
        
        Args:
            available_cards: Cards available for river
            board: Current board (flop + turn)
            our_hand: Player's hole cards
            
        Returns:
            EHS distribution array
        """
        n_available = len(available_cards)
        n_samples = min(self.n_simulations, n_available)
        
        # Sample river cards
        river_indices = np.random.choice(n_available, n_samples, replace=False)
        river_cards = available_cards[river_indices]
        
        ehs_values = []
        
        for river_card in river_cards:
            # Complete board with river
            full_board = np.concatenate([board, river_card.reshape(1, 2)])
            
            # Calculate EHS for this river
            ehs = self._calculate_ehs(our_hand, full_board, available_cards)
            ehs_values.append(ehs)
        
        # Convert to distribution (simplified for memory efficiency)
        # In production, this would be more sophisticated
        distribution = np.histogram(ehs_values, bins=self.n_clusters, range=(0, 1))[0]
        distribution = distribution.astype(np.float32) / n_samples
        
        return distribution
    
    def process_turn_combinations(self, turn_combos: List[np.ndarray]) -> dict:
        """
        Process all turn combinations with maximum memory safety.
        
        This is the main entry point that orchestrates the turn processing
        with aggressive memory management.
        
        Args:
            turn_combos: List of turn combinations
            
        Returns:
            LUT dictionary mapping combinations to cluster IDs
        """
        print(f"\n{'='*60}")
        print("TURN STAGE - Memory-Safe Processing")
        print(f"{'='*60}")
        
        # Phase 1: Process and store distributions
        kmeans = self.process_streaming(turn_combos)
        
        # Force cleanup before phase 2
        self.storage.flush()
        self.memory.emergency_cleanup()
        
        # Phase 2: Assign cluster labels
        self.assign_clusters_streaming(kmeans, turn_combos)
        
        # Phase 3: Build LUT with streaming
        lut = {}
        for partial_lut in self.build_lut_streaming():
            lut.update(partial_lut)
        
        print(f"✅ Turn processing complete. Final LUT size: {len(lut)}")
        self.memory.report_status()
        
        return lut