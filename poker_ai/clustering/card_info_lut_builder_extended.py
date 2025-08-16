"""Extended CardInfoLutBuilder for Texas Hold'em."""
import logging
import time
from pathlib import Path
from typing import Any, Dict

import joblib

from poker_ai.clustering.card_info_lut_builder import CardInfoLutBuilder
from poker_ai.clustering.preflop_texas_holdem import compute_preflop_lossless_abstraction_texas_holdem

log = logging.getLogger("poker_ai.clustering.runner")


class CardInfoLutBuilderExtended(CardInfoLutBuilder):
    """
    Extended version for Texas Hold'em (52 cards, 2-A).
    """
    
    def __init__(
        self,
        n_simulations_river: int,
        n_simulations_turn: int,
        n_simulations_flop: int,
        low_card_rank: int,
        high_card_rank: int,
        save_dir: str,
        deck_type: str = "texas_holdem",
    ):
        """Initialize with deck type specification."""
        self.deck_type = deck_type
        
        # Validate deck configuration for Texas Hold'em
        if low_card_rank != 2 or high_card_rank != 14:
            raise ValueError(
                f"Texas Hold'em requires ranks 2-14, got {low_card_rank}-{high_card_rank}"
            )
        
        super().__init__(
            n_simulations_river=n_simulations_river,
            n_simulations_turn=n_simulations_turn,
            n_simulations_flop=n_simulations_flop,
            low_card_rank=low_card_rank,
            high_card_rank=high_card_rank,
            save_dir=save_dir,
        )
        
        # Set file paths for Texas Hold'em
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
            # Use Texas Hold'em preflop abstraction
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