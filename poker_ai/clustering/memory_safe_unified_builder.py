"""
Memory-safe unified SQLite-backed LUT builder with streaming finalization.
Optimized for memory-constrained systems with proper batch processing throughout all phases.
"""

import gc
import os
import pickle
import sqlite3
import time
import zlib
import numpy as np
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any
from sklearn.cluster import MiniBatchKMeans
from tqdm import tqdm
import psutil
import joblib
import tempfile
import shutil

from poker_ai.clustering.unified_sqlite_builder import UnifiedSQLiteLUTBuilder


class MemorySafeUnifiedBuilder(UnifiedSQLiteLUTBuilder):
    """
    Memory-safe version with streaming finalization and aggressive memory management.
    Designed to complete LUT generation on systems with limited RAM.
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
        batch_size: int = 50,
        db_path: Optional[str] = None,
        checkpoint_dir: str = "lut_checkpoints",
        use_streaming_finalization: bool = True,
        aggressive_gc: bool = True,
        memory_safety_factor: float = 0.7,  # Use only 70% of limit for safety
        chunk_size: int = 10,  # Flush to DB every N items
    ):
        """
        Initialize memory-safe builder with additional safety features.
        
        Args:
            use_streaming_finalization: Stream data during finalization instead of loading all at once
            aggressive_gc: Run garbage collection more frequently
            memory_safety_factor: Use only this fraction of memory_limit_gb
            chunk_size: Number of items to process before flushing to database
        """
        super().__init__(
            n_simulations_river=n_simulations_river,
            n_simulations_turn=n_simulations_turn,
            n_simulations_flop=n_simulations_flop,
            low_card_rank=low_card_rank,
            high_card_rank=high_card_rank,
            save_dir=save_dir,
            n_river_clusters=n_river_clusters,
            n_turn_clusters=n_turn_clusters,
            n_flop_clusters=n_flop_clusters,
            n_preflop_clusters=n_preflop_clusters,
            memory_limit_gb=memory_limit_gb,
            batch_size=batch_size,
            db_path=db_path,
            checkpoint_dir=checkpoint_dir,
        )
        
        self.use_streaming_finalization = use_streaming_finalization
        self.aggressive_gc = aggressive_gc
        self.memory_safety_factor = memory_safety_factor
        self.effective_memory_limit = memory_limit_gb * memory_safety_factor
        self.chunk_size = chunk_size  # Add chunk_size parameter
        
        # Temporary file for streaming LUT assembly
        self.temp_lut_dir = Path(tempfile.mkdtemp(prefix="lut_temp_"))
        
        print(f"Memory-safe mode enabled:")
        print(f"  - Streaming finalization: {use_streaming_finalization}")
        print(f"  - Aggressive GC: {aggressive_gc}")
        print(f"  - Effective memory limit: {self.effective_memory_limit:.1f}GB")
        print(f"  - Chunk size (flush frequency): {chunk_size}")
    
    def _check_memory(self) -> bool:
        """Check if we're within safe memory limits."""
        current_usage = self._get_memory_usage_gb()
        
        # More aggressive check
        if current_usage > self.effective_memory_limit:
            print(f"⚠️ Memory usage {current_usage:.1f}GB exceeds safe limit {self.effective_memory_limit:.1f}GB")
            if self.aggressive_gc:
                gc.collect()
                time.sleep(1)
            return False
        
        return current_usage < self.effective_memory_limit * 0.9
    
    def _emergency_memory_cleanup(self):
        """Emergency cleanup when approaching memory limits."""
        print("🚨 Emergency memory cleanup triggered")
        
        # Clear any cached data
        if hasattr(self, '_cache'):
            self._cache.clear()
        
        # Force garbage collection multiple times
        for _ in range(3):
            gc.collect()
            time.sleep(0.5)
        
        # Clear SQLite cache
        if self.conn:
            self.conn.execute('PRAGMA shrink_memory')
            self.conn.execute('PRAGMA optimize')
        
        current_usage = self._get_memory_usage_gb()
        print(f"Memory after cleanup: {current_usage:.1f}GB")
    
    def _finalize_turn_clusters_streaming(self):
        """
        Memory-safe streaming version of turn finalization.
        Builds LUT in chunks and saves to temporary files.
        """
        print("Building turn LUT with streaming approach...")
        
        # Create temporary file for partial LUT
        temp_lut_path = self.temp_lut_dir / "turn_lut_partial.pkl"
        
        # Process in small chunks to avoid memory spike
        chunk_size = 100  # Process 100 combos at a time
        turn_lut_chunks = []
        
        # Get total count for progress bar
        cursor = self.conn.execute('SELECT COUNT(*) FROM turn_data')
        total_count = cursor.fetchone()[0]
        
        with tqdm(total=total_count, desc="Finalizing turn LUT") as pbar:
            for offset in range(0, total_count, chunk_size):
                # Check memory before processing chunk
                if not self._check_memory():
                    self._emergency_memory_cleanup()
                
                # Load small batch from database
                cursor = self.conn.execute('''
                    SELECT combo_id, combo_cards, cluster_id 
                    FROM turn_data 
                    ORDER BY combo_id
                    LIMIT ? OFFSET ?
                ''', (chunk_size, offset))
                
                chunk_lut = {}
                for row in cursor:
                    combo = pickle.loads(row[1])
                    cluster_id = row[2]
                    chunk_lut[tuple(combo)] = cluster_id
                
                # Save chunk to temporary file
                chunk_file = self.temp_lut_dir / f"turn_chunk_{offset}.pkl"
                with open(chunk_file, 'wb') as f:
                    pickle.dump(chunk_lut, f, protocol=pickle.HIGHEST_PROTOCOL)
                
                turn_lut_chunks.append(chunk_file)
                del chunk_lut
                
                if self.aggressive_gc and offset % 500 == 0:
                    gc.collect()
                
                pbar.update(min(chunk_size, total_count - offset))
        
        # Merge chunks into final LUT
        print("Merging turn LUT chunks...")
        turn_lut = {}
        
        for chunk_file in tqdm(turn_lut_chunks, desc="Merging chunks"):
            with open(chunk_file, 'rb') as f:
                chunk = pickle.load(f)
                turn_lut.update(chunk)
            
            # Delete chunk file immediately after loading
            chunk_file.unlink()
            
            # Check memory during merge
            if len(turn_lut) % 500 == 0 and not self._check_memory():
                # If memory pressure during merge, save and reload
                temp_save = self.temp_lut_dir / "turn_lut_temp.pkl"
                with open(temp_save, 'wb') as f:
                    pickle.dump(turn_lut, f, protocol=pickle.HIGHEST_PROTOCOL)
                
                del turn_lut
                gc.collect()
                
                with open(temp_save, 'rb') as f:
                    turn_lut = pickle.load(f)
                temp_save.unlink()
        
        self.card_info_lut["turn"] = turn_lut
        
        # Save checkpoint
        checkpoint_path = self.checkpoint_dir / "checkpoint_turn.joblib"
        joblib.dump({
            "turn": self.turn if hasattr(self, 'turn') else None,
            "centroids": self.turn_centroids if hasattr(self, 'turn_centroids') else None
        }, checkpoint_path, compress=3)
        
        print(f"✅ Turn LUT finalized with {len(turn_lut)} entries")
    
    def _finalize_turn_clusters(self):
        """Override parent method to use streaming version if enabled."""
        if self.use_streaming_finalization:
            self._finalize_turn_clusters_streaming()
        else:
            super()._finalize_turn_clusters()
    
    def _finalize_river_clusters_streaming(self):
        """Memory-safe streaming version of river finalization."""
        print("Building river LUT with streaming approach...")
        
        chunk_size = 200
        river_lut_chunks = []
        
        cursor = self.conn.execute('SELECT COUNT(*) FROM river_data')
        total_count = cursor.fetchone()[0]
        
        with tqdm(total=total_count, desc="Finalizing river LUT") as pbar:
            for offset in range(0, total_count, chunk_size):
                if not self._check_memory():
                    self._emergency_memory_cleanup()
                
                cursor = self.conn.execute('''
                    SELECT combo_id, combo_cards, cluster_id 
                    FROM river_data 
                    ORDER BY combo_id
                    LIMIT ? OFFSET ?
                ''', (chunk_size, offset))
                
                chunk_lut = {}
                for row in cursor:
                    combo = pickle.loads(row[1])
                    cluster_id = row[2]
                    chunk_lut[tuple(combo)] = cluster_id
                
                chunk_file = self.temp_lut_dir / f"river_chunk_{offset}.pkl"
                with open(chunk_file, 'wb') as f:
                    pickle.dump(chunk_lut, f, protocol=pickle.HIGHEST_PROTOCOL)
                
                river_lut_chunks.append(chunk_file)
                del chunk_lut
                
                if self.aggressive_gc and offset % 1000 == 0:
                    gc.collect()
                
                pbar.update(min(chunk_size, total_count - offset))
        
        # Merge chunks
        print("Merging river LUT chunks...")
        river_lut = {}
        
        for chunk_file in tqdm(river_lut_chunks, desc="Merging chunks"):
            with open(chunk_file, 'rb') as f:
                chunk = pickle.load(f)
                river_lut.update(chunk)
            chunk_file.unlink()
            
            if len(river_lut) % 1000 == 0 and not self._check_memory():
                self._emergency_memory_cleanup()
        
        self.card_info_lut["river"] = river_lut
        
        checkpoint_path = self.checkpoint_dir / "checkpoint_river.joblib"
        joblib.dump({
            "river": self.river if hasattr(self, 'river') else None,
            "centroids": self.river_centroids if hasattr(self, 'river_centroids') else None
        }, checkpoint_path, compress=3)
        
        print(f"✅ River LUT finalized with {len(river_lut)} entries")
    
    def _finalize_river_clusters(self):
        """Override parent method to use streaming version if enabled."""
        if self.use_streaming_finalization:
            self._finalize_river_clusters_streaming()
        else:
            super()._finalize_river_clusters()
    
    def _finalize_flop_clusters_streaming(self):
        """Memory-safe streaming version of flop finalization."""
        print("Building flop LUT with streaming approach...")
        
        chunk_size = 500
        flop_lut_chunks = []
        
        cursor = self.conn.execute('SELECT COUNT(*) FROM flop_data')
        total_count = cursor.fetchone()[0]
        
        with tqdm(total=total_count, desc="Finalizing flop LUT") as pbar:
            for offset in range(0, total_count, chunk_size):
                if not self._check_memory():
                    self._emergency_memory_cleanup()
                
                cursor = self.conn.execute('''
                    SELECT combo_id, combo_cards, cluster_id 
                    FROM flop_data 
                    ORDER BY combo_id
                    LIMIT ? OFFSET ?
                ''', (chunk_size, offset))
                
                chunk_lut = {}
                for row in cursor:
                    combo = pickle.loads(row[1])
                    cluster_id = row[2]
                    chunk_lut[tuple(combo)] = cluster_id
                
                chunk_file = self.temp_lut_dir / f"flop_chunk_{offset}.pkl"
                with open(chunk_file, 'wb') as f:
                    pickle.dump(chunk_lut, f, protocol=pickle.HIGHEST_PROTOCOL)
                
                flop_lut_chunks.append(chunk_file)
                del chunk_lut
                
                if self.aggressive_gc and offset % 2000 == 0:
                    gc.collect()
                
                pbar.update(min(chunk_size, total_count - offset))
        
        # Merge chunks
        print("Merging flop LUT chunks...")
        flop_lut = {}
        
        for chunk_file in tqdm(flop_lut_chunks, desc="Merging chunks"):
            with open(chunk_file, 'rb') as f:
                chunk = pickle.load(f)
                flop_lut.update(chunk)
            chunk_file.unlink()
            
            if len(flop_lut) % 5000 == 0 and not self._check_memory():
                self._emergency_memory_cleanup()
        
        self.card_info_lut["flop"] = flop_lut
        
        checkpoint_path = self.checkpoint_dir / "checkpoint_flop.joblib"
        joblib.dump({
            "flop": self.flop if hasattr(self, 'flop') else None,
            "centroids": self.flop_centroids if hasattr(self, 'flop_centroids') else None
        }, checkpoint_path, compress=3)
        
        print(f"✅ Flop LUT finalized with {len(flop_lut)} entries")
    
    def _finalize_flop_clusters(self):
        """Override parent method to use streaming version if enabled."""
        if self.use_streaming_finalization:
            self._finalize_flop_clusters_streaming()
        else:
            super()._finalize_flop_clusters()
    
    def cluster_turn(self):
        """Override turn clustering with more aggressive memory management."""
        print("\n" + "="*60)
        print("TURN STAGE - Memory-Safe Processing")
        print("="*60)
        
        # Check for checkpoint
        checkpoint = self._load_stage_checkpoint('turn')
        start_idx = 0
        kmeans = None
        
        if checkpoint:
            start_idx = checkpoint['last_processed_index']
            kmeans = checkpoint['kmeans']
            print(f"📂 Resuming from index {start_idx}/{len(self.turn)}")
        
        if start_idx >= len(self.turn):
            print("✅ Turn stage already complete")
            self._finalize_turn_clusters()
            return
        
        # Use chunk_size for processing - CRITICAL FIX
        process_chunk_size = min(self.chunk_size, 10)  # Never more than 10 at once
        
        # Initialize MiniBatchKMeans with smaller batch
        if kmeans is None:
            kmeans = MiniBatchKMeans(
                n_clusters=self.n_turn_clusters,
                batch_size=min(200, self.batch_size * 2),  # Smaller KMeans batch
                n_init=3,
                max_iter=100,
                random_state=42,
                verbose=0
            )
        
        print(f"Processing {len(self.turn)} turn combinations...")
        print(f"Using chunk size: {process_chunk_size} (flush every {self.chunk_size} items)")
        
        # Phase 1: Process and store turn distributions with aggressive flushing
        items_since_flush = 0
        
        with tqdm(total=len(self.turn) - start_idx, 
                  desc="Computing turn distributions") as pbar:
            
            for i in range(start_idx, len(self.turn), process_chunk_size):
                # Aggressive memory check
                if not self._check_memory():
                    self._emergency_memory_cleanup()
                    
                    # If still over limit, wait and retry
                    if not self._check_memory():
                        print(f"⚠️ Waiting for memory to free at {i}/{len(self.turn)}")
                        time.sleep(5)
                
                batch_end = min(i + process_chunk_size, len(self.turn))
                batch = self.turn[i:batch_end]
                
                batch_data = []
                for j, combo in enumerate(batch):
                    combo_id = i + j
                    
                    # Check if already processed
                    cursor = self.conn.execute(
                        'SELECT distribution FROM turn_data WHERE combo_id = ?',
                        (combo_id,)
                    )
                    row = cursor.fetchone()
                    
                    if row and row[0]:
                        dist = self._decompress_data(row[0])
                    else:
                        # Process new combination
                        dist = self.process_turn_ehs_distributions(combo)
                        
                        # Store in database with compression
                        self.conn.execute('''
                            INSERT OR REPLACE INTO turn_data 
                            (combo_id, combo_cards, distribution)
                            VALUES (?, ?, ?)
                        ''', (combo_id, pickle.dumps(combo), self._compress_data(dist)))
                        
                        items_since_flush += 1
                        
                        # Immediate cleanup of large objects
                        del combo
                    
                    batch_data.append(dist)
                
                # Partial fit on batch
                if batch_data:
                    X_batch = np.array(batch_data)
                    kmeans.partial_fit(X_batch)
                    
                    # Immediate cleanup
                    del X_batch
                    del batch_data
                
                # CRITICAL: Flush to database every chunk_size items
                if items_since_flush >= self.chunk_size:
                    self.conn.commit()
                    items_since_flush = 0
                    
                    # Force garbage collection after flush
                    if self.aggressive_gc:
                        gc.collect()
                    
                    # Show memory status
                    memory_usage = self._get_memory_usage_gb()
                    pbar.set_postfix(memory=f"{memory_usage:.1f}GB", flushed="✓")
                
                # More frequent checkpoints
                if (i - start_idx) % 20 == 0:  # Checkpoint every 20 items
                    self._save_stage_checkpoint('turn', i + len(batch), kmeans)
                    
                    # Commit any pending changes
                    if items_since_flush > 0:
                        self.conn.commit()
                        items_since_flush = 0
                        gc.collect()
                    
                    memory_usage = self._get_memory_usage_gb()
                    pbar.set_postfix(memory=f"{memory_usage:.1f}GB")
                
                pbar.update(len(batch))
                
                # Clear batch reference
                del batch
        
        # Final flush if any pending items
        if items_since_flush > 0:
            self.conn.commit()
            gc.collect()
        
        # Phase 2: Assign cluster labels with memory safety
        self._assign_turn_clusters_safe(kmeans)
        
        # Finalize
        self._finalize_turn_clusters()
        print(f"✅ Turn clustering complete. Memory: {self._get_memory_usage_gb():.1f}GB")
    
    def _assign_turn_clusters_safe(self, kmeans):
        """Memory-safe version of turn cluster assignment."""
        print("Assigning turn cluster labels (memory-safe)...")
        
        # Use chunk_size for safer batch processing
        safe_batch_size = min(self.chunk_size, 10)
        
        with tqdm(total=len(self.turn), desc="Assigning clusters") as pbar:
            for i in range(0, len(self.turn), safe_batch_size):
                batch_end = min(i + safe_batch_size, len(self.turn))
                
                # Check memory before loading batch
                if not self._check_memory():
                    self._emergency_memory_cleanup()
                
                # Load batch from database
                cursor = self.conn.execute('''
                    SELECT combo_id, distribution 
                    FROM turn_data 
                    WHERE combo_id >= ? AND combo_id < ?
                    ORDER BY combo_id
                ''', (i, batch_end))
                
                combo_ids = []
                batch_data = []
                
                for row in cursor:
                    combo_ids.append(row[0])
                    batch_data.append(self._decompress_data(row[1]))
                
                if batch_data:
                    # Predict clusters
                    X_batch = np.array(batch_data)
                    labels = kmeans.predict(X_batch)
                    
                    # Update database
                    for combo_id, label in zip(combo_ids, labels):
                        self.conn.execute(
                            'UPDATE turn_data SET cluster_id = ? WHERE combo_id = ?',
                            (int(label), combo_id)
                        )
                    
                    # Immediate cleanup
                    del X_batch
                    del batch_data
                    del combo_ids
                    del labels
                
                # Commit every chunk_size updates
                if (i % (self.chunk_size * safe_batch_size)) == 0:
                    self.conn.commit()
                    
                    if self.aggressive_gc:
                        gc.collect()
                
                pbar.update(batch_end - i)
        
        # Final commit
        self.conn.commit()
        
        # Save centroids
        self.turn_centroids = kmeans.cluster_centers_
        self._save_stage_checkpoint('turn', len(self.turn), kmeans, self.turn_centroids)
    
    def cleanup(self):
        """Clean up database, temporary files, and temp directory."""
        super().cleanup()
        
        # Clean up temporary directory
        if hasattr(self, 'temp_lut_dir') and self.temp_lut_dir.exists():
            try:
                shutil.rmtree(self.temp_lut_dir)
                print(f"Cleaned up temporary directory: {self.temp_lut_dir}")
            except Exception as e:
                print(f"Warning: Could not clean up temp directory: {e}")