"""Flop stage processor."""

import numpy as np
from typing import List

from .base_processor import BaseProcessor
from ..game_utility import GameUtility


class FlopProcessor(BaseProcessor):
    """Processes flop combinations."""
    
    def __init__(self,
                 storage,
                 memory_manager,
                 n_clusters: int,
                 n_simulations: int = 100,
                 batch_size: int = 50):
        """
        Initialize flop processor.
        
        Args:
            storage: Storage backend instance
            memory_manager: Memory manager instance
            n_clusters: Number of flop clusters
            n_simulations: Number of turn/river simulations
            batch_size: Processing batch size
        """
        super().__init__(storage, memory_manager, n_clusters, batch_size)
        self.n_simulations = n_simulations
        
        # Cards setup
        self.suits = [1, 2, 3, 4]
        self.ranks = list(range(2, 15))
        self._cards = np.array([[rank, suit] for suit in self.suits 
                                for rank in self.ranks])
    
    def compute_distribution(self, combo: np.ndarray) -> np.ndarray:
        """
        Compute flop distribution for a single combination.
        
        Args:
            combo: Flop combination (hand + flop cards)
            
        Returns:
            Flop distribution array
        """
        # Extract cards
        our_hand = combo[:2]
        board = combo[2:5]  # Flop only (3 cards)
        
        # Get available cards for turn and river
        unavailable = combo
        available_cards = self.get_available_cards(unavailable)
        
        # Simulate turn and river cards
        distribution = self.simulate_flop_ehs_distribution(
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
        simulations = min(10, len(available_cards) * (len(available_cards) - 1) // 2)
        
        for _ in range(simulations):
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
        
        return wins / simulations if simulations > 0 else 0.5
    
    def get_available_cards(self, unavailable_cards: np.ndarray) -> np.ndarray:
        """Get cards that are still available."""
        mask = np.ones(len(self._cards), dtype=bool)
        
        for card in unavailable_cards:
            matches = (self._cards[:, 0] == card[0]) & (self._cards[:, 1] == card[1])
            mask &= ~matches
        
        return self._cards[mask]
    
    def simulate_flop_ehs_distribution(self,
                                      available_cards: np.ndarray,
                                      board: np.ndarray,
                                      our_hand: np.ndarray) -> np.ndarray:
        """
        Simulate turn and river cards to compute flop EHS distribution.
        
        Args:
            available_cards: Cards available for turn/river
            board: Current flop (3 cards)
            our_hand: Player's hole cards
            
        Returns:
            EHS distribution array
        """
        n_available = len(available_cards)
        n_samples = min(self.n_simulations, n_available * (n_available - 1) // 2)
        
        ehs_values = []
        
        for _ in range(n_samples):
            # Sample turn and river
            turn_river = np.random.choice(n_available, 2, replace=False)
            turn_card = available_cards[turn_river[0]]
            river_card = available_cards[turn_river[1]]
            
            # Complete board
            full_board = np.concatenate([
                board,
                turn_card.reshape(1, 2),
                river_card.reshape(1, 2)
            ])
            
            # Calculate EHS
            ehs = self._calculate_ehs(our_hand, full_board, available_cards)
            ehs_values.append(ehs)
        
        # Convert to distribution
        distribution = np.histogram(ehs_values, bins=self.n_clusters, range=(0, 1))[0]
        distribution = distribution.astype(np.float32) / n_samples
        
        return distribution
    
    def process_flop_combinations(self, flop_combos: List[np.ndarray]) -> dict:
        """
        Process all flop combinations.
        
        Args:
            flop_combos: List of flop combinations
            
        Returns:
            LUT dictionary mapping combinations to cluster IDs
        """
        print(f"\n{'='*60}")
        print("FLOP STAGE - Processing")
        print(f"{'='*60}")
        
        # Process with base class streaming method
        kmeans = self.process_streaming(flop_combos)
        
        # Cleanup
        self.storage.flush()
        self.memory.periodic_gc()
        
        # Assign clusters
        self.assign_clusters_streaming(kmeans, flop_combos)
        
        # Build LUT
        lut = {}
        for partial_lut in self.build_lut_streaming():
            lut.update(partial_lut)
        
        print(f"✅ Flop processing complete. Final LUT size: {len(lut)}")
        self.memory.report_status()
        
        return lut