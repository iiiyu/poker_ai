"""River stage processor."""

import numpy as np
from typing import List

from .base_processor import BaseProcessor
from ..game_utility import GameUtility


class RiverProcessor(BaseProcessor):
    """Processes river combinations."""
    
    def __init__(self,
                 storage,
                 memory_manager,
                 n_clusters: int,
                 n_simulations: int = 100,
                 batch_size: int = 50):
        """
        Initialize river processor.
        
        Args:
            storage: Storage backend instance
            memory_manager: Memory manager instance
            n_clusters: Number of river clusters
            n_simulations: Number of simulations
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
        Compute river distribution (EHS) for a single combination.
        
        Args:
            combo: River combination (hand + full board)
            
        Returns:
            River EHS value as single-element array
        """
        # Extract cards
        our_hand = combo[:2]
        board = combo[2:7]  # Full 5-card board
        
        # Get available cards for opponent
        unavailable = combo
        available_cards = self.get_available_cards(unavailable)
        
        # Calculate EHS (Expected Hand Strength)
        ehs = self._calculate_river_ehs(our_hand, board, available_cards)
        
        # Return as array for consistency
        return np.array([ehs], dtype=np.float32)
    
    def _calculate_river_ehs(self, our_hand: np.ndarray, board: np.ndarray, 
                            available_cards: np.ndarray) -> float:
        """
        Calculate Expected Hand Strength on river.
        
        Args:
            our_hand: Player's hole cards
            board: Full 5-card board
            available_cards: Cards available for opponent
            
        Returns:
            EHS value (win probability)
        """
        wins = 0
        total = 0
        
        # Sample opponent hands and calculate win rate
        for _ in range(self.n_simulations):
            # Sample opponent hand
            opp_hand = np.random.choice(len(available_cards), 2, replace=False)
            opp_cards = available_cards[opp_hand]
            
            # Create game state and get winner
            game = GameUtility(our_hand=our_hand, board=board, cards=self._cards)
            game.opp_hand = opp_cards  # Set opponent hand
            
            winner = game.get_winner()
            if winner == 0:  # We win
                wins += 1
            elif winner == 2:  # Tie
                wins += 0.5
            total += 1
        
        return wins / total if total > 0 else 0.5
    
    def get_available_cards(self, unavailable_cards: np.ndarray) -> np.ndarray:
        """Get cards that are still available."""
        mask = np.ones(len(self._cards), dtype=bool)
        
        for card in unavailable_cards:
            matches = (self._cards[:, 0] == card[0]) & (self._cards[:, 1] == card[1])
            mask &= ~matches
        
        return self._cards[mask]
    
    def process_river_combinations(self, river_combos: List[np.ndarray]) -> dict:
        """
        Process all river combinations.
        
        Args:
            river_combos: List of river combinations
            
        Returns:
            LUT dictionary mapping combinations to cluster IDs
        """
        print(f"\n{'='*60}")
        print("RIVER STAGE - Processing")
        print(f"{'='*60}")
        
        # Process with base class streaming method
        kmeans = self.process_streaming(river_combos)
        
        # Cleanup
        self.storage.flush()
        self.memory.periodic_gc()
        
        # Assign clusters
        self.assign_clusters_streaming(kmeans, river_combos)
        
        # Build LUT
        lut = {}
        for partial_lut in self.build_lut_streaming():
            lut.update(partial_lut)
        
        print(f"✅ River processing complete. Final LUT size: {len(lut)}")
        self.memory.report_status()
        
        return lut