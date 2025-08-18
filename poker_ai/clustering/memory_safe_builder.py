"""
Memory-safe version of UnifiedSQLiteLUTBuilder with streaming finalization.
Designed to work on systems with limited RAM by processing data in chunks.
"""

import os
import gc
import pickle
import sqlite3
import psutil
import tempfile
import numpy as np
from pathlib import Path
from typing import Optional, Dict, Tuple, List
from tqdm import tqdm
import logging

from .unified_sqlite_builder import UnifiedSQLiteLUTBuilder

logger = logging.getLogger(__name__)

class MemorySafeUnifiedBuilder(UnifiedSQLiteLUTBuilder):
    """
    Memory-safe version that processes turn combinations in chunks during finalization.
    """
    
    def __init__(self, *args, safety_factor: float = 0.7, chunk_size: int = 100, **kwargs):
        """
        Initialize with additional memory safety parameters.
        
        Args:
            safety_factor: Use only this fraction of memory_limit_gb (default 0.7)
            chunk_size: Number of turn combos to process at once during finalization
        """
        super().__init__(*args, **kwargs)
        self.safety_factor = safety_factor
        self.effective_memory_limit = self.memory_limit_gb * safety_factor
        self.chunk_size = chunk_size
        self.temp_dir = Path(tempfile.mkdtemp(prefix="lut_chunks_"))
        logger.info(f"Memory-safe mode: limit={self.effective_memory_limit:.1f}GB, chunk_size={chunk_size}")
    
    def _get_memory_usage(self) -> float:
        """Get current memory usage in GB."""
        process = psutil.Process()
        return process.memory_info().rss / (1024 ** 3)
    
    def _check_memory_pressure(self) -> bool:
        """Check if we're approaching memory limit."""
        usage = self._get_memory_usage()
        return usage > self.effective_memory_limit
    
    def _emergency_cleanup(self):
        """Emergency memory cleanup when approaching limits."""
        logger.warning("Emergency memory cleanup triggered!")
        
        # Clear any cached data
        if hasattr(self, '_cache'):
            self._cache.clear()
        
        # Force garbage collection
        gc.collect()
        gc.collect()  # Double collect for thorough cleanup
        
        # Clear SQLite cache
        conn = sqlite3.connect(self.db_path)
        conn.execute("PRAGMA shrink_memory")
        conn.close()
        
        logger.info(f"Memory after cleanup: {self._get_memory_usage():.2f}GB")
    
    def _finalize_turn_clusters(self) -> np.ndarray:
        """
        Memory-safe version that processes turn combinations in chunks.
        """
        logger.info(f"Starting memory-safe turn finalization (chunk_size={self.chunk_size})")
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get total number of combos
        cursor.execute("SELECT COUNT(DISTINCT combo) FROM turn_data")
        n_combos = cursor.fetchone()[0]
        
        # Initialize output array
        turn_abstraction_buckets = np.zeros(n_combos, dtype=np.int32)
        
        # Process in chunks
        chunk_files = []
        for chunk_start in tqdm(range(0, n_combos, self.chunk_size), desc="Processing turn chunks"):
            chunk_end = min(chunk_start + self.chunk_size, n_combos)
            
            # Check memory before processing chunk
            if self._check_memory_pressure():
                self._emergency_cleanup()
            
            # Process chunk
            chunk_data = self._process_turn_chunk(chunk_start, chunk_end, cursor)
            
            # Save chunk to disk to free memory
            chunk_file = self.temp_dir / f"chunk_{chunk_start}_{chunk_end}.pkl"
            with open(chunk_file, 'wb') as f:
                pickle.dump(chunk_data, f)
            chunk_files.append((chunk_start, chunk_end, chunk_file))
            
            # Clear chunk from memory
            del chunk_data
            gc.collect()
        
        cursor.close()
        conn.close()
        
        # Merge chunks back into final array
        logger.info("Merging chunks into final array...")
        for chunk_start, chunk_end, chunk_file in tqdm(chunk_files, desc="Merging chunks"):
            with open(chunk_file, 'rb') as f:
                chunk_data = pickle.load(f)
            
            turn_abstraction_buckets[chunk_start:chunk_end] = chunk_data
            
            # Clean up chunk file
            chunk_file.unlink()
            del chunk_data
            gc.collect()
        
        # Clean up temp directory
        self.temp_dir.rmdir()
        
        logger.info(f"Turn finalization complete. Final memory: {self._get_memory_usage():.2f}GB")
        return turn_abstraction_buckets
    
    def _process_turn_chunk(self, start_idx: int, end_idx: int, cursor: sqlite3.Cursor) -> np.ndarray:
        """
        Process a chunk of turn combinations.
        """
        chunk_size = end_idx - start_idx
        chunk_buckets = np.zeros(chunk_size, dtype=np.int32)
        
        # Get cluster model
        cursor.execute("SELECT model FROM turn_models WHERE id = 1")
        model_blob = cursor.fetchone()[0]
        kmeans_model = pickle.loads(model_blob)
        
        # Process each combo in chunk
        for i, combo_idx in enumerate(range(start_idx, end_idx)):
            # Get distributions for this combo
            cursor.execute(
                "SELECT distribution FROM turn_data WHERE combo = ? AND distribution IS NOT NULL",
                (combo_idx,)
            )
            
            distributions = []
            for row in cursor:
                if row[0] is not None:
                    distributions.append(pickle.loads(row[0]))
            
            if distributions:
                # Average distributions and predict cluster
                avg_distribution = np.mean(distributions, axis=0)
                cluster = kmeans_model.predict([avg_distribution])[0]
                chunk_buckets[i] = cluster
            
            # Periodic memory check within chunk
            if i % 10 == 0 and self._check_memory_pressure():
                self._emergency_cleanup()
        
        return chunk_buckets
    
    def _process_turn_batch(self, combo_indices: List[int], batch_size: int = None):
        """
        Override to use smaller micro-batches for turn processing.
        """
        if batch_size is None:
            batch_size = max(1, self.batch_size // 5)  # Use 1/5 of normal batch size
        
        logger.info(f"Processing turn batch with micro-batch size: {batch_size}")
        
        # Process in even smaller chunks if memory is tight
        for i in range(0, len(combo_indices), batch_size):
            if self._check_memory_pressure():
                self._emergency_cleanup()
                batch_size = max(1, batch_size // 2)  # Halve batch size if memory tight
            
            micro_batch = combo_indices[i:i+batch_size]
            super()._process_turn_batch(micro_batch, batch_size=len(micro_batch))
            
            # Force cleanup after each micro-batch
            gc.collect()
    
    def compute(self, n_river_clusters: int, n_turn_clusters: int, n_flop_clusters: int):
        """
        Override compute to use memory-safe processing throughout.
        """
        logger.info(f"Starting memory-safe compute (safety_factor={self.safety_factor})")
        logger.info(f"Effective memory limit: {self.effective_memory_limit:.1f}GB")
        
        # Monitor memory throughout
        initial_memory = self._get_memory_usage()
        logger.info(f"Initial memory usage: {initial_memory:.2f}GB")
        
        try:
            # Call parent compute with memory monitoring
            result = super().compute(n_river_clusters, n_turn_clusters, n_flop_clusters)
            
            final_memory = self._get_memory_usage()
            logger.info(f"Final memory usage: {final_memory:.2f}GB")
            logger.info(f"Peak memory increase: {final_memory - initial_memory:.2f}GB")
            
            return result
            
        except MemoryError as e:
            logger.error(f"Memory error during compute: {e}")
            self._emergency_cleanup()
            raise
        
        except Exception as e:
            logger.error(f"Error during compute: {e}")
            raise
        
        finally:
            # Final cleanup
            gc.collect()
            
            # Clean up temp directory if it exists
            if hasattr(self, 'temp_dir') and self.temp_dir.exists():
                for file in self.temp_dir.glob('*'):
                    file.unlink()
                self.temp_dir.rmdir()