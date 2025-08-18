"""Unified LUT builder - single entry point for all clustering operations."""

import time
from pathlib import Path
from typing import Optional, Dict
import numpy as np
import joblib

from .core import StorageBackend, MemoryManager
from .processors import RiverProcessor, TurnProcessor, FlopProcessor
from .card_combos import CardCombos
from .preflop_texas_holdem import get_preflop_clusters_texas_holdem


class UnifiedLUTBuilder:
    """
    Single, clean implementation for building poker LUTs.
    Replaces all 6 redundant builders with one unified architecture.
    """
    
    def __init__(self,
                 # Simulation parameters
                 n_simulations_river: int = 100,
                 n_simulations_turn: int = 100,
                 n_simulations_flop: int = 100,
                 
                 # Card range
                 low_card_rank: int = 2,
                 high_card_rank: int = 14,
                 
                 # Clustering parameters
                 n_river_clusters: int = 200,
                 n_turn_clusters: int = 200,
                 n_flop_clusters: int = 200,
                 n_preflop_clusters: int = 169,
                 
                 # Memory management
                 memory_limit_gb: float = 50.0,
                 memory_safety_factor: float = 0.7,
                 aggressive_gc: bool = True,
                 
                 # Processing parameters
                 batch_size: int = 50,
                 chunk_size: int = 10,
                 
                 # Storage
                 db_path: Optional[str] = None,
                 save_dir: str = ".",
                 checkpoint_dir: str = "lut_checkpoints"):
        """
        Initialize unified LUT builder.
        
        This single builder replaces:
        - CardInfoLutBuilder
        - CardInfoLutBuilderExtended
        - MemoryEfficientLUTBuilder
        - UnifiedSQLiteLUTBuilder
        - MemorySafeUnifiedBuilder
        - MemorySafeBuilder
        
        Args:
            n_simulations_*: Number of simulations for each stage
            low_card_rank: Lowest card rank (2)
            high_card_rank: Highest card rank (14 for Ace)
            n_*_clusters: Number of clusters for each stage
            memory_limit_gb: Maximum memory usage
            memory_safety_factor: Use only this fraction of memory limit
            aggressive_gc: Whether to run garbage collection aggressively
            batch_size: Number of combinations to process at once
            chunk_size: Number of items to process before flushing to database
            db_path: Path to SQLite database
            save_dir: Directory to save final LUT file
            checkpoint_dir: Directory for checkpoints
        """
        # Store parameters
        self.n_simulations = {
            'river': n_simulations_river,
            'turn': n_simulations_turn,
            'flop': n_simulations_flop
        }
        
        self.n_clusters = {
            'river': n_river_clusters,
            'turn': n_turn_clusters,
            'flop': n_flop_clusters,
            'preflop': n_preflop_clusters
        }
        
        self.low_card_rank = low_card_rank
        self.high_card_rank = high_card_rank
        self.batch_size = batch_size
        self.save_dir = Path(save_dir)
        
        # Initialize core components
        db_path = Path(db_path or "clustering_data.db")
        self.storage = StorageBackend(db_path, chunk_size=chunk_size)
        self.memory = MemoryManager(
            memory_limit_gb=memory_limit_gb,
            safety_factor=memory_safety_factor,
            aggressive_gc=aggressive_gc
        )
        
        # Initialize card combinations
        self.card_combos = CardCombos(low_card_rank, high_card_rank)
        self.river = self.card_combos.river
        self.turn = self.card_combos.turn
        self.flop = self.card_combos.flop
        
        # Initialize processors
        self.river_processor = RiverProcessor(
            self.storage, self.memory, 
            n_river_clusters, n_simulations_river, batch_size
        )
        
        self.turn_processor = TurnProcessor(
            self.storage, self.memory,
            n_turn_clusters, n_simulations_turn, batch_size
        )
        
        self.flop_processor = FlopProcessor(
            self.storage, self.memory,
            n_flop_clusters, n_simulations_flop, batch_size
        )
        
        # Preflop will be handled directly in compute()
        
        print("=" * 60)
        print("Unified LUT Builder Initialized")
        print("=" * 60)
        print(f"Database: {db_path}")
        print(f"Memory limit: {memory_limit_gb}GB (effective: {memory_limit_gb * memory_safety_factor:.1f}GB)")
        print(f"Batch size: {batch_size}, Chunk size: {chunk_size}")
        print(f"Combinations: River={len(self.river)}, Turn={len(self.turn)}, Flop={len(self.flop)}")
    
    def compute(self):
        """
        Main computation method - processes all stages.
        
        This replaces the compute methods from all 6 redundant builders
        with a single, clean implementation.
        """
        start_time = time.time()
        
        print("\n" + "=" * 60)
        print("Starting LUT Generation")
        print("=" * 60)
        
        # Process each stage
        results = {}
        
        # 1. River stage (simplest, smallest memory footprint)
        if self._should_process_stage('river'):
            results['river'] = self.river_processor.process_river_combinations(self.river)
        else:
            print("✓ River stage already complete")
            results['river'] = self._load_stage_lut('river')
        
        # 2. Turn stage (memory-critical)
        if self._should_process_stage('turn'):
            results['turn'] = self.turn_processor.process_turn_combinations(self.turn)
        else:
            print("✓ Turn stage already complete")
            results['turn'] = self._load_stage_lut('turn')
        
        # 3. Flop stage
        if self._should_process_stage('flop'):
            results['flop'] = self.flop_processor.process_flop_combinations(self.flop)
        else:
            print("✓ Flop stage already complete")
            results['flop'] = self._load_stage_lut('flop')
        
        # 4. Preflop (doesn't need processing, just get LUT)
        results['preflop'] = get_preflop_clusters_texas_holdem()
        
        # Save final LUT
        self._save_final_lut(results)
        
        elapsed = time.time() - start_time
        print(f"\n{'=' * 60}")
        print(f"✅ LUT Generation Complete!")
        print(f"Time: {elapsed/60:.1f} minutes")
        print(f"Peak memory: {self.memory.peak_memory_gb:.1f}GB")
        print(f"{'=' * 60}")
    
    def _should_process_stage(self, stage: str) -> bool:
        """Check if a stage needs processing based on database state."""
        checkpoint = self.storage.load_checkpoint(stage)
        
        if stage == 'river':
            total = len(self.river)
        elif stage == 'turn':
            total = len(self.turn)
        else:
            total = len(self.flop)
        
        if checkpoint and checkpoint['last_processed_index'] >= total:
            return False
        
        return True
    
    def _load_stage_lut(self, stage: str) -> dict:
        """Load existing LUT for a stage from database."""
        lut = {}
        for combo, cluster_id in self.storage.stream_clusters(stage):
            lut[tuple(combo)] = cluster_id
        return lut
    
    def _save_final_lut(self, results: Dict):
        """Save the final combined LUT to file."""
        output_path = self.save_dir / "card_info_lut.joblib"
        
        lut_data = {
            'river_clusters': results.get('river', {}),
            'turn_clusters': results.get('turn', {}),
            'flop_clusters': results.get('flop', {}),
            'preflop_clusters': results.get('preflop', {}),
            
            # Metadata
            'n_clusters': self.n_clusters,
            'n_simulations': self.n_simulations,
            'card_range': (self.low_card_rank, self.high_card_rank)
        }
        
        joblib.dump(lut_data, output_path, compress=3)
        
        size_mb = output_path.stat().st_size / (1024 * 1024)
        print(f"\n✅ LUT saved to: {output_path}")
        print(f"   File size: {size_mb:.1f}MB")
    
    def cleanup(self):
        """Clean up resources."""
        self.storage.cleanup()
        self.memory.report_status()
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.cleanup()