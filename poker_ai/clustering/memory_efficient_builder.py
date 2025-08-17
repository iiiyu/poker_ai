"""
Memory-efficient LUT builder that processes data in chunks to stay within memory limits.
"""

import gc
import os
import sys
import time
import psutil
import joblib
import numpy as np
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from collections import defaultdict
from sklearn.cluster import MiniBatchKMeans
from tqdm import tqdm

from poker_ai.clustering.card_info_lut_builder import CardInfoLutBuilder


class MemoryEfficientLUTBuilder(CardInfoLutBuilder):
    """
    Memory-efficient version of CardInfoLUTBuilder that processes data in chunks
    and uses disk-based caching to handle large datasets within memory constraints.
    """
    
    def __init__(
        self,
        n_simulations_river: int = 10,
        n_simulations_turn: int = 10,
        n_simulations_flop: int = 10,
        low_card_rank: int = 2,
        high_card_rank: int = 14,
        save_dir: str = ".",
        n_river_clusters: int = 200,
        n_turn_clusters: int = 200,
        n_flop_clusters: int = 200,
        n_preflop_clusters: int = 169,
        memory_limit_gb: float = 50.0,
        chunk_size: Optional[int] = None,
        use_disk_cache: bool = True,
        checkpoint_dir: str = "lut_checkpoints",
    ):
        """
        Initialize memory-efficient LUT builder.
        
        Args:
            memory_limit_gb: Maximum memory to use in GB (default 50GB)
            chunk_size: Size of chunks to process at once (auto-calculated if None)
            use_disk_cache: Whether to use disk for temporary storage
            checkpoint_dir: Directory to save checkpoints
        """
        super().__init__(
            n_simulations_river=n_simulations_river,
            n_simulations_turn=n_simulations_turn,
            n_simulations_flop=n_simulations_flop,
            low_card_rank=low_card_rank,
            high_card_rank=high_card_rank,
            save_dir=save_dir,
        )
        
        # Store clustering parameters
        self.n_river_clusters = n_river_clusters
        self.n_turn_clusters = n_turn_clusters
        self.n_flop_clusters = n_flop_clusters
        self.n_preflop_clusters = n_preflop_clusters
        
        self.memory_limit_gb = memory_limit_gb
        self.memory_limit_bytes = int(memory_limit_gb * 1024 * 1024 * 1024)
        self.use_disk_cache = use_disk_cache
        self.checkpoint_dir = Path(checkpoint_dir)
        self.checkpoint_dir.mkdir(exist_ok=True)
        
        # Calculate optimal chunk size based on memory limit
        if chunk_size is None:
            self.chunk_size = self._calculate_optimal_chunk_size()
        else:
            self.chunk_size = chunk_size
            
        print(f"Memory-efficient mode: limit={memory_limit_gb}GB, chunk_size={self.chunk_size}")
    
    def _calculate_optimal_chunk_size(self) -> int:
        """Calculate optimal chunk size based on memory limit."""
        # Estimate memory per item (roughly 8KB per distribution)
        memory_per_item = 8 * 1024
        
        # Use 30% of memory limit for chunk processing
        chunk_memory = self.memory_limit_bytes * 0.3
        
        # Calculate chunk size
        chunk_size = int(chunk_memory / memory_per_item)
        
        # Clamp to reasonable range
        chunk_size = max(100, min(chunk_size, 10000))
        
        return chunk_size
    
    def _get_memory_usage_gb(self) -> float:
        """Get current memory usage in GB."""
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 * 1024 * 1024)
    
    def _check_memory(self) -> bool:
        """Check if we're within memory limits."""
        current_usage = self._get_memory_usage_gb()
        return current_usage < self.memory_limit_gb * 0.9  # 90% threshold
    
    def _save_checkpoint(self, stage: str, data: Dict):
        """Save checkpoint for a stage."""
        checkpoint_path = self.checkpoint_dir / f"checkpoint_{stage}.joblib"
        joblib.dump(data, checkpoint_path, compress=3)
        print(f"✅ Saved checkpoint: {checkpoint_path}")
    
    def _load_checkpoint(self, stage: str) -> Optional[Dict]:
        """Load checkpoint for a stage."""
        checkpoint_path = self.checkpoint_dir / f"checkpoint_{stage}.joblib"
        if checkpoint_path.exists():
            print(f"📂 Loading checkpoint: {checkpoint_path}")
            return joblib.load(checkpoint_path)
        return None
    
    def cluster_river(self):
        """Memory-efficient river clustering."""
        print("Starting memory-efficient river clustering...")
        
        # Check for existing checkpoint
        checkpoint = self._load_checkpoint("river")
        if checkpoint:
            self.river = checkpoint["river"]
            self.river_dists = checkpoint["dists"]
            self.river_centroids = checkpoint["centroids"]
            print("✅ Loaded river from checkpoint")
            return
        
        # Process in chunks
        river_chunks = []
        dist_chunks = []
        
        total_combos = len(self.river)
        n_chunks = (total_combos + self.chunk_size - 1) // self.chunk_size
        
        print(f"Processing {total_combos} river combinations in {n_chunks} chunks...")
        
        with tqdm(total=n_chunks, desc="River chunks") as pbar:
            for i in range(0, total_combos, self.chunk_size):
                chunk_end = min(i + self.chunk_size, total_combos)
                chunk = list(self.river)[i:chunk_end]
                
                # Process chunk
                chunk_dists = []
                for combo in chunk:
                    if not self._check_memory():
                        # Force garbage collection if memory is tight
                        gc.collect()
                        time.sleep(0.5)
                    
                    dist = self.process_river_ehs(combo)
                    chunk_dists.append(dist)
                
                river_chunks.extend(chunk)
                dist_chunks.extend(chunk_dists)
                
                pbar.update(1)
                
                # Clear temporary variables
                del chunk_dists
                gc.collect()
        
        # Cluster using MiniBatchKMeans (memory-efficient)
        print(f"Clustering {len(dist_chunks)} river distributions...")
        
        X = np.array(dist_chunks)
        
        # Use MiniBatchKMeans for memory efficiency
        kmeans = MiniBatchKMeans(
            n_clusters=self.n_river_clusters,
            batch_size=min(1000, len(X) // 10),
            n_init=3,
            max_iter=100,
            random_state=42,
            verbose=1
        )
        
        labels = kmeans.fit_predict(X)
        
        # Store results
        self.river = river_chunks
        self.river_dists = X
        self.river_centroids = kmeans.cluster_centers_
        
        # Map to clusters using same format as parent
        river_lut = {}
        for combo, label in zip(self.river, labels):
            river_lut[tuple(combo)] = label
        
        self.card_info_lut["river"] = river_lut
        
        # Save checkpoint
        self._save_checkpoint("river", {
            "river": self.river,
            "dists": self.river_dists,
            "centroids": self.river_centroids
        })
        
        # Clean up
        del X, labels
        gc.collect()
        
        print(f"✅ River clustering complete. Memory usage: {self._get_memory_usage_gb():.1f}GB")
    
    def cluster_turn(self):
        """Memory-efficient turn clustering with streaming."""
        print("Starting memory-efficient turn clustering...")
        
        # Check for existing checkpoint
        checkpoint = self._load_checkpoint("turn")
        if checkpoint:
            self.turn = checkpoint["turn"]
            self.turn_dists = checkpoint["dists"]
            self.turn_centroids = checkpoint["centroids"]
            print("✅ Loaded turn from checkpoint")
            return
        
        # Use streaming approach for turn
        print(f"Processing turn combinations with streaming...")
        
        # Initialize MiniBatchKMeans
        kmeans = MiniBatchKMeans(
            n_clusters=self.n_turn_clusters,
            batch_size=500,
            n_init=3,
            max_iter=100,
            random_state=42,
            verbose=1
        )
        
        # Process and cluster in batches
        turn_combos = []
        batch_dists = []
        batch_num = 0
        
        total_combos = len(self.turn)
        
        with tqdm(total=total_combos, desc="Turn processing") as pbar:
            for i, combo in enumerate(self.turn):
                if not self._check_memory():
                    gc.collect()
                    time.sleep(0.5)
                
                # Process distribution
                dist = self.process_turn_ehs_distributions(combo)
                turn_combos.append(combo)
                batch_dists.append(dist)
                
                # Partial fit when batch is full
                if len(batch_dists) >= self.chunk_size:
                    X_batch = np.array(batch_dists)
                    kmeans.partial_fit(X_batch)
                    
                    # Clear batch
                    del X_batch
                    batch_dists = []
                    batch_num += 1
                    gc.collect()
                
                pbar.update(1)
        
        # Fit remaining batch
        if batch_dists:
            X_batch = np.array(batch_dists)
            kmeans.partial_fit(X_batch)
            del X_batch
            gc.collect()
        
        print("Assigning turn clusters...")
        
        # Assign clusters in batches
        all_labels = []
        for i in range(0, len(turn_combos), self.chunk_size):
            chunk_end = min(i + self.chunk_size, len(turn_combos))
            chunk = turn_combos[i:chunk_end]
            
            # Recompute distributions for this chunk
            chunk_dists = []
            for combo in chunk:
                dist = self.process_turn_ehs_distributions(combo)
                chunk_dists.append(dist)
            
            X_chunk = np.array(chunk_dists)
            labels = kmeans.predict(X_chunk)
            all_labels.extend(labels)
            
            del X_chunk, chunk_dists
            gc.collect()
        
        # Store results
        self.turn = turn_combos
        self.turn_centroids = kmeans.cluster_centers_
        
        # Map to clusters using same format as parent
        turn_lut = {}
        for combo, label in zip(self.turn, all_labels):
            turn_lut[tuple(combo)] = label
        
        self.card_info_lut["turn"] = turn_lut
        
        # Save checkpoint
        self._save_checkpoint("turn", {
            "turn": self.turn,
            "dists": None,  # Don't save large distributions
            "centroids": self.turn_centroids
        })
        
        print(f"✅ Turn clustering complete. Memory usage: {self._get_memory_usage_gb():.1f}GB")
    
    def cluster_flop(self):
        """Memory-efficient flop clustering."""
        print("Starting memory-efficient flop clustering...")
        
        # Check for existing checkpoint
        checkpoint = self._load_checkpoint("flop")
        if checkpoint:
            self.flop = checkpoint["flop"]
            self.flop_dists = checkpoint.get("dists")
            self.flop_centroids = checkpoint["centroids"]
            print("✅ Loaded flop from checkpoint")
            return
        
        # Similar streaming approach as turn
        print(f"Processing flop combinations with streaming...")
        
        kmeans = MiniBatchKMeans(
            n_clusters=self.n_flop_clusters,
            batch_size=500,
            n_init=3,
            max_iter=100,
            random_state=42,
            verbose=1
        )
        
        flop_combos = []
        batch_dists = []
        
        total_combos = len(self.flop)
        
        with tqdm(total=total_combos, desc="Flop processing") as pbar:
            for combo in self.flop:
                if not self._check_memory():
                    gc.collect()
                    time.sleep(0.5)
                
                dist = self.process_flop_potential_aware_distributions(combo)
                flop_combos.append(combo)
                batch_dists.append(dist)
                
                if len(batch_dists) >= self.chunk_size:
                    X_batch = np.array(batch_dists)
                    kmeans.partial_fit(X_batch)
                    del X_batch
                    batch_dists = []
                    gc.collect()
                
                pbar.update(1)
        
        # Fit remaining
        if batch_dists:
            X_batch = np.array(batch_dists)
            kmeans.partial_fit(X_batch)
            del X_batch
            gc.collect()
        
        # Assign clusters
        print("Assigning flop clusters...")
        all_labels = []
        
        for i in range(0, len(flop_combos), self.chunk_size):
            chunk_end = min(i + self.chunk_size, len(flop_combos))
            chunk = flop_combos[i:chunk_end]
            
            chunk_dists = []
            for combo in chunk:
                dist = self.process_flop_potential_aware_distributions(combo)
                chunk_dists.append(dist)
            
            X_chunk = np.array(chunk_dists)
            labels = kmeans.predict(X_chunk)
            all_labels.extend(labels)
            
            del X_chunk, chunk_dists
            gc.collect()
        
        # Store results
        self.flop = flop_combos
        self.flop_centroids = kmeans.cluster_centers_
        
        # Map to clusters using same format as parent
        flop_lut = {}
        for combo, label in zip(self.flop, all_labels):
            flop_lut[tuple(combo)] = label
        
        self.card_info_lut["flop"] = flop_lut
        
        # Save checkpoint
        self._save_checkpoint("flop", {
            "flop": self.flop,
            "dists": None,
            "centroids": self.flop_centroids
        })
        
        print(f"✅ Flop clustering complete. Memory usage: {self._get_memory_usage_gb():.1f}GB")
    
    def cluster_preflop(self):
        """Handle preflop clustering using lossless abstraction."""
        from poker_ai.clustering.preflop import compute_preflop_lossless_abstraction
        
        print("Computing preflop lossless abstraction...")
        self.card_info_lut["pre_flop"] = compute_preflop_lossless_abstraction(
            self.low_card_rank, self.high_card_rank
        )
        print("✅ Preflop clustering complete")
    
    def build(self):
        """Build LUT with memory management."""
        print(f"Building LUT with memory limit: {self.memory_limit_gb}GB")
        print(f"Initial memory usage: {self._get_memory_usage_gb():.1f}GB")
        
        # Cluster each stage with checkpointing
        stages = [
            ("preflop", self.cluster_preflop),
            ("river", self.cluster_river),
            ("turn", self.cluster_turn),
            ("flop", self.cluster_flop)
        ]
        
        for stage_name, stage_func in stages:
            print(f"\n{'='*60}")
            print(f"Processing {stage_name.upper()}")
            print(f"{'='*60}")
            
            try:
                stage_func()
                
                # Save LUT after each stage
                joblib.dump(self.card_info_lut, self.card_info_lut_path, compress=3)
                print(f"✅ Saved LUT after {stage_name}")
                
                # Force cleanup
                gc.collect()
                
            except MemoryError:
                print(f"❌ Memory error in {stage_name}. Try reducing clusters or chunk size.")
                raise
            except Exception as e:
                print(f"❌ Error in {stage_name}: {e}")
                raise
        
        # Save centroids
        centroids_path = Path(self.card_info_lut_path).parent / "centroids.joblib"
        centroids = {
            "river": self.river_centroids,
            "turn": self.turn_centroids,
            "flop": self.flop_centroids
        }
        joblib.dump(centroids, centroids_path, compress=3)
        
        print(f"\n{'='*60}")
        print(f"✅ LUT generation complete!")
        print(f"Final memory usage: {self._get_memory_usage_gb():.1f}GB")
        print(f"LUT saved to: {self.card_info_lut_path}")
        print(f"Centroids saved to: {centroids_path}")
        print(f"{'='*60}")