"""Extended CardInfoLutBuilder that supports both short deck and full Texas Hold'em."""
import logging
import time
from pathlib import Path
from typing import Any, Dict

import joblib

from poker_ai.clustering.card_info_lut_builder import CardInfoLutBuilder
from poker_ai.clustering.preflop import compute_preflop_lossless_abstraction
from poker_ai.clustering.preflop_texas_holdem import compute_preflop_lossless_abstraction_texas_holdem

log = logging.getLogger("poker_ai.clustering.runner")


class CardInfoLutBuilderExtended(CardInfoLutBuilder):
    """
    Extended version that supports both short deck and full Texas Hold'em.
    
    Attributes
    ----------
    deck_type : str
        Either "short_deck" (20 cards, 10-A) or "texas_holdem" (52 cards, 2-A)
    """
    
    def __init__(
        self,
        n_simulations_river: int,
        n_simulations_turn: int,
        n_simulations_flop: int,
        low_card_rank: int,
        high_card_rank: int,
        save_dir: str,
        deck_type: str = "short_deck",
    ):
        """Initialize with deck type specification."""
        self.deck_type = deck_type
        
        # Validate deck configuration
        if deck_type == "short_deck":
            if low_card_rank != 10 or high_card_rank != 14:
                raise ValueError(
                    f"Short deck requires ranks 10-14, got {low_card_rank}-{high_card_rank}"
                )
        elif deck_type == "texas_holdem":
            if low_card_rank != 2 or high_card_rank != 14:
                raise ValueError(
                    f"Texas Hold'em requires ranks 2-14, got {low_card_rank}-{high_card_rank}"
                )
        else:
            raise ValueError(f"Unknown deck_type: {deck_type}")
        
        super().__init__(
            n_simulations_river=n_simulations_river,
            n_simulations_turn=n_simulations_turn,
            n_simulations_flop=n_simulations_flop,
            low_card_rank=low_card_rank,
            high_card_rank=high_card_rank,
            save_dir=save_dir,
        )
        
        # Update file paths based on deck type
        if deck_type == "texas_holdem":
            self.card_info_lut_path = Path(save_dir) / "texas_holdem_card_info_lut.joblib"
            self.centroid_path = Path(save_dir) / "texas_holdem_centroids.joblib"
        
        # Try to load existing files
        try:
            self.card_info_lut: Dict[str, Any] = joblib.load(self.card_info_lut_path)
            self.centroids: Dict[str, Any] = joblib.load(self.centroid_path)
        except FileNotFoundError:
            self.centroids: Dict[str, Any] = {}
            self.card_info_lut: Dict[str, Any] = {}
    
    def compute(
        self, n_river_clusters: int, n_turn_clusters: int, n_flop_clusters: int,
    ):
        """Compute all clusters and save to card_info_lut dictionary.
        
        Will attempt to load previous progress and will save after each cluster
        is computed. Uses appropriate preflop abstraction based on deck type.
        """
        log.info(f"Starting computation of clusters for {self.deck_type}.")
        start = time.time()
        
        if "pre_flop" not in self.card_info_lut:
            # Use appropriate preflop abstraction based on deck type
            if self.deck_type == "short_deck":
                self.card_info_lut["pre_flop"] = compute_preflop_lossless_abstraction(
                    builder=self
                )
            else:  # texas_holdem
                self.card_info_lut["pre_flop"] = compute_preflop_lossless_abstraction_texas_holdem(
                    builder=self
                )
            joblib.dump(self.card_info_lut, self.card_info_lut_path)
            log.info(f"Computed preflop abstractions for {self.deck_type}")
        
        if "river" not in self.card_info_lut:
            self.card_info_lut["river"] = self._compute_river_clusters(
                n_river_clusters,
            )
            joblib.dump(self.card_info_lut, self.card_info_lut_path)
            joblib.dump(self.centroids, self.centroid_path)
            
        if "turn" not in self.card_info_lut:
            self.card_info_lut["turn"] = self._compute_turn_clusters(n_turn_clusters)
            joblib.dump(self.card_info_lut, self.card_info_lut_path)
            joblib.dump(self.centroids, self.centroid_path)
            
        if "flop" not in self.card_info_lut:
            self.card_info_lut["flop"] = self._compute_flop_clusters(n_flop_clusters)
            joblib.dump(self.card_info_lut, self.card_info_lut_path)
            joblib.dump(self.centroids, self.centroid_path)
            
        end = time.time()
        log.info(
            f"Finished computation of clusters for {self.deck_type} - "
            f"took {end - start} seconds."
        )