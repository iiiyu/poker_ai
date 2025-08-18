"""
Incremental turn processor with database-backed storage to prevent memory overflow.
This solves the issue where turn processing crashes at 98% due to memory accumulation.
"""

import gc
import os
import pickle
import sqlite3
import time
import numpy as np
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from sklearn.cluster import MiniBatchKMeans
from tqdm import tqdm
import psutil
import joblib

from poker_ai.clustering.memory_efficient_builder import MemoryEfficientLUTBuilder


class IncrementalTurnProcessor(MemoryEfficientLUTBuilder):
    """
    Enhanced turn processor that uses database-backed storage to prevent memory overflow.
    Processes turn combinations in micro-batches with immediate cleanup.
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.db_path = Path("turn_processing.db")
        self.micro_batch_size = 20  # Process only 20 combinations at a time
        self.turn_checkpoint_file = self.checkpoint_dir / "turn_progress.joblib"
        
    def _init_turn_database(self):
        """Initialize SQLite database for turn processing with optimizations."""
        conn = sqlite3.connect(str(self.db_path))
        
        # Performance optimizations for temporary storage
        conn.execute('PRAGMA journal_mode = WAL')  # Write-ahead logging
        conn.execute('PRAGMA synchronous = NORMAL')  # Faster writes
        conn.execute('PRAGMA cache_size = -64000')  # 64MB cache
        conn.execute('PRAGMA temp_store = MEMORY')  # Use memory for temp tables
        conn.execute('PRAGMA mmap_size = 268435456')  # 256MB memory-mapped I/O
        
        conn.execute('''
            CREATE TABLE IF NOT EXISTS turn_distributions (
                combo_id INTEGER PRIMARY KEY,
                combo_cards BLOB,
                distribution BLOB,
                cluster_id INTEGER DEFAULT -1
            )
        ''')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_cluster ON turn_distributions(cluster_id)')
        conn.commit()
        return conn
    
    def _get_turn_progress(self, conn) -> int:
        """Get the number of already processed turn combinations."""
        cursor = conn.execute('SELECT COUNT(*) FROM turn_distributions WHERE distribution IS NOT NULL')
        return cursor.fetchone()[0]
    
    def _save_turn_progress(self, last_idx: int, kmeans_state: Optional[MiniBatchKMeans] = None):
        """Save progress checkpoint for turn processing."""
        checkpoint = {
            'last_processed_index': last_idx,
            'timestamp': time.time()
        }
        if kmeans_state is not None:
            checkpoint['kmeans_state'] = kmeans_state
        joblib.dump(checkpoint, self.turn_checkpoint_file, compress=3)
    
    def _load_turn_progress(self) -> Optional[Dict]:
        """Load turn processing checkpoint."""
        if self.turn_checkpoint_file.exists():
            return joblib.load(self.turn_checkpoint_file)
        return None
    
    def cluster_turn(self):
        """Memory-efficient turn clustering with database backing and micro-batching."""
        print("Starting incremental turn clustering with database backing...")
        
        # Check for existing checkpoint
        checkpoint = self._load_checkpoint("turn")
        if checkpoint:
            self.turn = checkpoint["turn"]
            self.turn_centroids = checkpoint["centroids"]
            print("✅ Loaded turn from checkpoint")
            return
        
        # Initialize database
        conn = self._init_turn_database()
        
        # Check existing progress
        processed_count = self._get_turn_progress(conn)
        start_idx = processed_count
        
        if processed_count > 0:
            print(f"📂 Resuming from {processed_count}/{len(self.turn)} turn combinations")
        
        # Initialize MiniBatchKMeans
        kmeans = MiniBatchKMeans(
            n_clusters=self.n_turn_clusters,
            batch_size=min(500, self.micro_batch_size * 10),
            n_init=3,
            max_iter=100,
            random_state=42,
            verbose=0
        )
        
        # Load kmeans state if resuming
        turn_progress = self._load_turn_progress()
        if turn_progress and 'kmeans_state' in turn_progress:
            kmeans = turn_progress['kmeans_state']
            print(f"📂 Loaded KMeans state from checkpoint")
        
        # Phase 1: Process distributions and train incrementally
        print(f"Phase 1: Processing turn distributions...")
        total_combos = len(self.turn)
        
        with tqdm(total=total_combos - start_idx, 
                  initial=0,
                  desc="Processing turn combinations") as pbar:
            
            for i in range(start_idx, total_combos, self.micro_batch_size):
                # Check memory before processing
                if not self._check_memory():
                    print(f"⚠️ Memory pressure detected at {i}/{total_combos}")
                    gc.collect()
                    time.sleep(2)
                
                batch_end = min(i + self.micro_batch_size, total_combos)
                batch = self.turn[i:batch_end]
                batch_dists = []
                
                # Process micro-batch
                for j, combo in enumerate(batch):
                    combo_id = i + j
                    
                    # Check if already processed
                    cursor = conn.execute(
                        'SELECT distribution FROM turn_distributions WHERE combo_id = ?',
                        (combo_id,)
                    )
                    row = cursor.fetchone()
                    
                    if row and row[0] is not None:
                        # Already processed, load from database
                        dist = pickle.loads(row[0])
                    else:
                        # Process new combination
                        dist = self.process_turn_ehs_distributions(combo)
                        
                        # Store immediately in database
                        conn.execute(
                            'INSERT OR REPLACE INTO turn_distributions (combo_id, combo_cards, distribution) VALUES (?, ?, ?)',
                            (combo_id, pickle.dumps(combo), pickle.dumps(dist))
                        )
                    
                    batch_dists.append(dist)
                
                # Partial fit on this micro-batch
                if batch_dists:
                    X_batch = np.array(batch_dists)
                    kmeans.partial_fit(X_batch)
                    
                    # Clear batch from memory
                    del X_batch
                    del batch_dists
                
                # Commit to database
                conn.commit()
                
                # Save checkpoint every 100 combinations
                if (i - start_idx) % 100 == 0:
                    self._save_turn_progress(i + len(batch), kmeans)
                    
                    # Force cleanup
                    gc.collect()
                    
                    # Report memory usage
                    memory_usage = self._get_memory_usage_gb()
                    pbar.set_postfix(memory=f"{memory_usage:.1f}GB")
                
                pbar.update(len(batch))
        
        print("Phase 2: Assigning final cluster labels...")
        
        # Phase 2: Assign cluster labels using stored distributions
        with tqdm(total=total_combos, desc="Assigning clusters") as pbar:
            for i in range(0, total_combos, self.micro_batch_size * 5):  # Larger batches for labeling
                batch_end = min(i + self.micro_batch_size * 5, total_combos)
                
                # Load distributions from database
                cursor = conn.execute(
                    'SELECT combo_id, distribution FROM turn_distributions WHERE combo_id >= ? AND combo_id < ? ORDER BY combo_id',
                    (i, batch_end)
                )
                
                batch_data = []
                combo_ids = []
                
                for row in cursor:
                    combo_ids.append(row[0])
                    batch_data.append(pickle.loads(row[1]))
                
                if batch_data:
                    # Predict clusters
                    X_batch = np.array(batch_data)
                    labels = kmeans.predict(X_batch)
                    
                    # Update database with cluster assignments
                    for combo_id, label in zip(combo_ids, labels):
                        conn.execute(
                            'UPDATE turn_distributions SET cluster_id = ? WHERE combo_id = ?',
                            (int(label), combo_id)
                        )
                    
                    # Clear batch
                    del X_batch
                    del batch_data
                
                conn.commit()
                gc.collect()
                
                pbar.update(batch_end - i)
        
        # Phase 3: Build final lookup table
        print("Phase 3: Building turn lookup table...")
        
        turn_lut = {}
        cursor = conn.execute(
            'SELECT combo_id, combo_cards, cluster_id FROM turn_distributions ORDER BY combo_id'
        )
        
        for row in cursor:
            combo = pickle.loads(row[1])
            cluster_id = row[2]
            turn_lut[tuple(combo)] = cluster_id
        
        # Store results
        self.turn = list(self.turn)  # Ensure it's a list
        self.turn_centroids = kmeans.cluster_centers_
        self.card_info_lut["turn"] = turn_lut
        
        # Save checkpoint
        self._save_checkpoint("turn", {
            "turn": self.turn,
            "dists": None,  # Don't save distributions to save memory
            "centroids": self.turn_centroids
        })
        
        # Cleanup database
        conn.close()
        if self.db_path.exists():
            print(f"💾 Turn database size: {self.db_path.stat().st_size / (1024**3):.2f}GB")
            # Optionally delete database after successful completion
            # self.db_path.unlink()
        
        # Clean up checkpoint file
        if self.turn_checkpoint_file.exists():
            self.turn_checkpoint_file.unlink()
        
        print(f"✅ Turn clustering complete. Memory usage: {self._get_memory_usage_gb():.1f}GB")
    
    def build(self):
        """Build LUT with enhanced turn processing."""
        print(f"Building LUT with incremental turn processor")
        print(f"Memory limit: {self.memory_limit_gb}GB")
        print(f"Initial memory usage: {self._get_memory_usage_gb():.1f}GB")
        
        # Cluster each stage with checkpointing
        stages = [
            ("preflop", self.cluster_preflop),
            ("river", self.cluster_river),
            ("turn", self.cluster_turn),  # Uses our enhanced method
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
            "flop": self.flop_centroids if hasattr(self, 'flop_centroids') else None
        }
        joblib.dump(centroids, centroids_path, compress=3)
        
        print(f"\n{'='*60}")
        print(f"✅ LUT generation complete!")
        print(f"Final memory usage: {self._get_memory_usage_gb():.1f}GB")
        print(f"LUT saved to: {self.card_info_lut_path}")
        print(f"Centroids saved to: {centroids_path}")
        print(f"{'='*60}")