"""Unified SQLite storage backend with automatic chunking and compression."""

import gc
import pickle
import sqlite3
import zlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import numpy as np


class StorageBackend:
    """Unified SQLite backend with automatic chunking and compression."""
    
    def __init__(self, db_path: Path, chunk_size: int = 10):
        """
        Initialize storage backend.
        
        Args:
            db_path: Path to SQLite database
            chunk_size: Number of items to buffer before flushing to database
        """
        self.db_path = Path(db_path)
        self.chunk_size = chunk_size
        self.buffer = []
        self.conn = None
        self._init_database()
    
    def _init_database(self):
        """Initialize database tables for all stages."""
        self.conn = sqlite3.connect(str(self.db_path))
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.execute("PRAGMA cache_size=-64000")  # 64MB cache
        self.conn.execute("PRAGMA temp_store=MEMORY")
        
        # Create tables for each stage
        for stage in ['river', 'turn', 'flop']:
            self.conn.execute(f'''
                CREATE TABLE IF NOT EXISTS {stage}_data (
                    combo_id INTEGER PRIMARY KEY,
                    combo_cards BLOB NOT NULL,
                    distribution BLOB,
                    cluster_id INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            # Create indices for faster queries
            self.conn.execute(f'''
                CREATE INDEX IF NOT EXISTS idx_{stage}_cluster 
                ON {stage}_data(cluster_id)
            ''')
        
        # Create checkpoint table
        self.conn.execute('''
            CREATE TABLE IF NOT EXISTS checkpoints (
                stage TEXT PRIMARY KEY,
                last_processed_index INTEGER,
                kmeans_state BLOB,
                centroids BLOB,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.conn.commit()
    
    def store_distribution(self, stage: str, combo_id: int, 
                          combo: np.ndarray, data: np.ndarray):
        """
        Buffer and batch-write distributions.
        
        Args:
            stage: Processing stage ('river', 'turn', or 'flop')
            combo_id: Unique identifier for the combination
            combo: Card combination array
            data: Distribution data to store
        """
        self.buffer.append((stage, combo_id, combo, data))
        
        if len(self.buffer) >= self.chunk_size:
            self.flush()
    
    def flush(self):
        """Write buffered data to database and clear memory."""
        if not self.buffer:
            return
        
        try:
            with self.conn:
                for stage, combo_id, combo, data in self.buffer:
                    compressed = zlib.compress(pickle.dumps(data), level=1)
                    self.conn.execute(f'''
                        INSERT OR REPLACE INTO {stage}_data 
                        (combo_id, combo_cards, distribution)
                        VALUES (?, ?, ?)
                    ''', (combo_id, pickle.dumps(combo), compressed))
        finally:
            # Always clear buffer and collect garbage
            self.buffer.clear()
            gc.collect()
    
    def get_distribution(self, stage: str, combo_id: int) -> Optional[np.ndarray]:
        """
        Retrieve a distribution from the database.
        
        Args:
            stage: Processing stage
            combo_id: Combination identifier
            
        Returns:
            Decompressed distribution array or None if not found
        """
        cursor = self.conn.execute(
            f'SELECT distribution FROM {stage}_data WHERE combo_id = ?',
            (combo_id,)
        )
        row = cursor.fetchone()
        
        if row and row[0]:
            return pickle.loads(zlib.decompress(row[0]))
        return None
    
    def get_batch_distributions(self, stage: str, start_id: int, 
                               end_id: int) -> List[Tuple[int, np.ndarray]]:
        """
        Retrieve a batch of distributions.
        
        Args:
            stage: Processing stage
            start_id: Starting combo_id (inclusive)
            end_id: Ending combo_id (exclusive)
            
        Returns:
            List of (combo_id, distribution) tuples
        """
        cursor = self.conn.execute(f'''
            SELECT combo_id, distribution 
            FROM {stage}_data 
            WHERE combo_id >= ? AND combo_id < ?
            ORDER BY combo_id
        ''', (start_id, end_id))
        
        results = []
        for combo_id, dist_blob in cursor:
            if dist_blob:
                dist = pickle.loads(zlib.decompress(dist_blob))
                results.append((combo_id, dist))
        
        return results
    
    def update_cluster_ids(self, stage: str, updates: List[Tuple[int, int]]):
        """
        Batch update cluster IDs.
        
        Args:
            stage: Processing stage
            updates: List of (cluster_id, combo_id) tuples
        """
        with self.conn:
            for cluster_id, combo_id in updates:
                self.conn.execute(
                    f'UPDATE {stage}_data SET cluster_id = ? WHERE combo_id = ?',
                    (cluster_id, combo_id)
                )
    
    def save_checkpoint(self, stage: str, last_index: int, 
                       kmeans_state: Any = None, centroids: Any = None):
        """
        Save processing checkpoint.
        
        Args:
            stage: Processing stage
            last_index: Last processed index
            kmeans_state: Serializable KMeans state
            centroids: Cluster centroids
        """
        kmeans_blob = pickle.dumps(kmeans_state) if kmeans_state else None
        centroids_blob = pickle.dumps(centroids) if centroids is not None else None
        
        self.conn.execute('''
            INSERT OR REPLACE INTO checkpoints 
            (stage, last_processed_index, kmeans_state, centroids, updated_at)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''', (stage, last_index, kmeans_blob, centroids_blob))
        self.conn.commit()
    
    def load_checkpoint(self, stage: str) -> Optional[Dict[str, Any]]:
        """
        Load processing checkpoint.
        
        Args:
            stage: Processing stage
            
        Returns:
            Checkpoint data or None if not found
        """
        cursor = self.conn.execute(
            'SELECT last_processed_index, kmeans_state, centroids FROM checkpoints WHERE stage = ?',
            (stage,)
        )
        row = cursor.fetchone()
        
        if row:
            return {
                'last_processed_index': row[0],
                'kmeans': pickle.loads(row[1]) if row[1] else None,
                'centroids': pickle.loads(row[2]) if row[2] else None
            }
        return None
    
    def stream_clusters(self, stage: str, batch_size: int = 100):
        """
        Stream cluster assignments from database.
        
        Args:
            stage: Processing stage
            batch_size: Number of records to fetch at once
            
        Yields:
            Tuples of (combo_cards, cluster_id)
        """
        cursor = self.conn.execute(f'''
            SELECT combo_cards, cluster_id 
            FROM {stage}_data 
            WHERE cluster_id IS NOT NULL
            ORDER BY combo_id
        ''')
        
        while True:
            rows = cursor.fetchmany(batch_size)
            if not rows:
                break
            
            for combo_blob, cluster_id in rows:
                combo = pickle.loads(combo_blob)
                yield combo, cluster_id
    
    def get_stage_count(self, stage: str) -> int:
        """Get total number of combinations for a stage."""
        cursor = self.conn.execute(
            f'SELECT COUNT(*) FROM {stage}_data WHERE distribution IS NOT NULL'
        )
        return cursor.fetchone()[0]
    
    def cleanup(self):
        """Close database connection and cleanup resources."""
        self.flush()  # Flush any remaining buffer
        if self.conn:
            self.conn.close()
            self.conn = None
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.cleanup()