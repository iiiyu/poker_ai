"""
Unified SQLite-backed LUT builder that handles ALL stages consistently.
This solves memory issues for river, turn, and flop stages by using database backing throughout.
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

from poker_ai.clustering.card_info_lut_builder import CardInfoLutBuilder


class UnifiedSQLiteLUTBuilder(CardInfoLutBuilder):
    """
    Unified SQLite-backed LUT builder that processes all stages with consistent database backing.
    Ensures memory safety by never keeping all distributions in memory simultaneously.
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
    ):
        """
        Initialize unified SQLite-backed LUT builder.
        
        Args:
            batch_size: Number of combinations to process at once
            db_path: Path to SQLite database (default: clustering_data.db)
            checkpoint_dir: Directory for checkpoint files
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
        
        # Memory and processing settings
        self.memory_limit_gb = memory_limit_gb
        self.batch_size = batch_size
        
        # Database and checkpoint paths
        self.db_path = Path(db_path or "clustering_data.db")
        self.checkpoint_dir = Path(checkpoint_dir)
        self.checkpoint_dir.mkdir(exist_ok=True)
        
        # Initialize database connection
        self.conn = None
        self._init_database()
        
        print(f"Unified SQLite LUT Builder initialized")
        print(f"Database: {self.db_path}")
        print(f"Batch size: {batch_size}")
        print(f"Memory limit: {memory_limit_gb}GB")
    
    def _init_database(self):
        """Initialize SQLite database with optimized settings and schema for all stages."""
        self.conn = sqlite3.connect(str(self.db_path))
        
        # Performance optimizations
        self.conn.execute('PRAGMA journal_mode = WAL')
        self.conn.execute('PRAGMA synchronous = NORMAL')
        self.conn.execute('PRAGMA cache_size = -64000')  # 64MB cache
        self.conn.execute('PRAGMA temp_store = MEMORY')
        self.conn.execute('PRAGMA mmap_size = 268435456')  # 256MB mmap
        
        # Create unified schema for all stages
        self.conn.execute('''
            CREATE TABLE IF NOT EXISTS river_data (
                combo_id INTEGER PRIMARY KEY,
                combo_cards BLOB NOT NULL,
                ehs_data BLOB,  -- 3D vector
                cluster_id INTEGER DEFAULT -1,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.conn.execute('''
            CREATE TABLE IF NOT EXISTS turn_data (
                combo_id INTEGER PRIMARY KEY,
                combo_cards BLOB NOT NULL,
                distribution BLOB,  -- Compressed distribution over river clusters
                cluster_id INTEGER DEFAULT -1,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.conn.execute('''
            CREATE TABLE IF NOT EXISTS flop_data (
                combo_id INTEGER PRIMARY KEY,
                combo_cards BLOB NOT NULL,
                distribution BLOB,  -- Compressed distribution over turn clusters
                cluster_id INTEGER DEFAULT -1,
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.conn.execute('''
            CREATE TABLE IF NOT EXISTS checkpoints (
                stage TEXT PRIMARY KEY,
                last_processed_index INTEGER,
                kmeans_state BLOB,
                centroids BLOB,
                metadata BLOB,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Create indices for performance
        self.conn.execute('CREATE INDEX IF NOT EXISTS idx_river_cluster ON river_data(cluster_id)')
        self.conn.execute('CREATE INDEX IF NOT EXISTS idx_turn_cluster ON turn_data(cluster_id)')
        self.conn.execute('CREATE INDEX IF NOT EXISTS idx_flop_cluster ON flop_data(cluster_id)')
        
        self.conn.commit()
    
    def _get_memory_usage_gb(self) -> float:
        """Get current memory usage in GB."""
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 * 1024 * 1024)
    
    def _check_memory(self) -> bool:
        """Check if we're within memory limits."""
        current_usage = self._get_memory_usage_gb()
        return current_usage < self.memory_limit_gb * 0.9
    
    def _compress_data(self, data: np.ndarray) -> bytes:
        """Compress numpy array for storage."""
        return zlib.compress(pickle.dumps(data), level=1)
    
    def _decompress_data(self, data: bytes) -> np.ndarray:
        """Decompress stored data back to numpy array."""
        return pickle.loads(zlib.decompress(data))
    
    def _save_stage_checkpoint(self, stage: str, last_idx: int, 
                               kmeans: Optional[MiniBatchKMeans] = None,
                               centroids: Optional[np.ndarray] = None,
                               metadata: Optional[Dict] = None):
        """Save checkpoint for a processing stage."""
        self.conn.execute('''
            INSERT OR REPLACE INTO checkpoints 
            (stage, last_processed_index, kmeans_state, centroids, metadata, updated_at)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''', (
            stage,
            last_idx,
            pickle.dumps(kmeans) if kmeans else None,
            pickle.dumps(centroids) if centroids is not None else None,
            pickle.dumps(metadata) if metadata else None
        ))
        self.conn.commit()
    
    def _load_stage_checkpoint(self, stage: str) -> Optional[Dict]:
        """Load checkpoint for a processing stage."""
        cursor = self.conn.execute(
            'SELECT last_processed_index, kmeans_state, centroids, metadata FROM checkpoints WHERE stage = ?',
            (stage,)
        )
        row = cursor.fetchone()
        if row:
            return {
                'last_processed_index': row[0],
                'kmeans': pickle.loads(row[1]) if row[1] else None,
                'centroids': pickle.loads(row[2]) if row[2] else None,
                'metadata': pickle.loads(row[3]) if row[3] else None
            }
        return None
    
    def cluster_river(self):
        """Process river stage with SQLite backing."""
        print("\n" + "="*60)
        print("RIVER STAGE - SQLite Backed Processing")
        print("="*60)
        
        # Check for checkpoint
        checkpoint = self._load_stage_checkpoint('river')
        start_idx = 0
        kmeans = None
        
        if checkpoint:
            start_idx = checkpoint['last_processed_index']
            kmeans = checkpoint['kmeans']
            print(f"📂 Resuming from index {start_idx}/{len(self.river)}")
        
        if start_idx >= len(self.river):
            print("✅ River stage already complete")
            self._finalize_river_clusters()
            return
        
        # Initialize MiniBatchKMeans
        if kmeans is None:
            kmeans = MiniBatchKMeans(
                n_clusters=self.n_river_clusters,
                batch_size=min(1000, self.batch_size * 10),
                n_init=3,
                max_iter=100,
                random_state=42,
                verbose=0
            )
        
        print(f"Processing {len(self.river)} river combinations...")
        
        # Phase 1: Process and store river EHS data
        with tqdm(total=len(self.river) - start_idx, 
                  desc="Computing river EHS") as pbar:
            
            for i in range(start_idx, len(self.river), self.batch_size):
                batch_end = min(i + self.batch_size, len(self.river))
                batch = self.river[i:batch_end]
                
                batch_data = []
                for j, combo in enumerate(batch):
                    combo_id = i + j
                    
                    # Check if already processed
                    cursor = self.conn.execute(
                        'SELECT ehs_data FROM river_data WHERE combo_id = ?',
                        (combo_id,)
                    )
                    row = cursor.fetchone()
                    
                    if row and row[0]:
                        ehs = self._decompress_data(row[0])
                    else:
                        # Process new combination
                        ehs = self.process_river_ehs(combo)
                        
                        # Store in database
                        self.conn.execute('''
                            INSERT OR REPLACE INTO river_data 
                            (combo_id, combo_cards, ehs_data)
                            VALUES (?, ?, ?)
                        ''', (combo_id, pickle.dumps(combo), self._compress_data(ehs)))
                    
                    batch_data.append(ehs)
                
                # Partial fit on batch
                if batch_data:
                    X_batch = np.array(batch_data)
                    kmeans.partial_fit(X_batch)
                    del X_batch, batch_data
                
                # Checkpoint every 500 combinations
                if (i - start_idx) % 500 == 0:
                    self._save_stage_checkpoint('river', i + len(batch), kmeans)
                    gc.collect()
                    
                    memory_usage = self._get_memory_usage_gb()
                    pbar.set_postfix(memory=f"{memory_usage:.1f}GB")
                
                self.conn.commit()
                pbar.update(len(batch))
        
        # Phase 2: Assign cluster labels
        self._assign_river_clusters(kmeans)
        
        # Finalize
        self._finalize_river_clusters()
        print(f"✅ River clustering complete. Memory: {self._get_memory_usage_gb():.1f}GB")
    
    def _assign_river_clusters(self, kmeans):
        """Assign cluster labels to river combinations."""
        print("Assigning river cluster labels...")
        
        with tqdm(total=len(self.river), desc="Assigning clusters") as pbar:
            for i in range(0, len(self.river), self.batch_size * 5):
                batch_end = min(i + self.batch_size * 5, len(self.river))
                
                # Load batch from database
                cursor = self.conn.execute('''
                    SELECT combo_id, ehs_data 
                    FROM river_data 
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
                            'UPDATE river_data SET cluster_id = ? WHERE combo_id = ?',
                            (int(label), combo_id)
                        )
                    
                    del X_batch, batch_data
                
                self.conn.commit()
                gc.collect()
                pbar.update(batch_end - i)
        
        # Save centroids
        self.river_centroids = kmeans.cluster_centers_
        self._save_stage_checkpoint('river', len(self.river), kmeans, self.river_centroids)
    
    def _finalize_river_clusters(self):
        """Build final river lookup table from database."""
        river_lut = {}
        cursor = self.conn.execute('''
            SELECT combo_id, combo_cards, cluster_id 
            FROM river_data 
            ORDER BY combo_id
        ''')
        
        for row in cursor:
            combo = pickle.loads(row[1])
            cluster_id = row[2]
            river_lut[tuple(combo)] = cluster_id
        
        self.card_info_lut["river"] = river_lut
        
        # Save checkpoint
        checkpoint_path = self.checkpoint_dir / "checkpoint_river.joblib"
        joblib.dump({
            "river": self.river,
            "centroids": self.river_centroids if hasattr(self, 'river_centroids') else None
        }, checkpoint_path, compress=3)
    
    def cluster_turn(self):
        """Process turn stage with SQLite backing."""
        print("\n" + "="*60)
        print("TURN STAGE - SQLite Backed Processing")
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
        
        # Initialize MiniBatchKMeans
        if kmeans is None:
            kmeans = MiniBatchKMeans(
                n_clusters=self.n_turn_clusters,
                batch_size=min(500, self.batch_size * 5),
                n_init=3,
                max_iter=100,
                random_state=42,
                verbose=0
            )
        
        print(f"Processing {len(self.turn)} turn combinations...")
        micro_batch = 20  # Even smaller batches for turn
        
        # Phase 1: Process and store turn distributions
        with tqdm(total=len(self.turn) - start_idx, 
                  desc="Computing turn distributions") as pbar:
            
            for i in range(start_idx, len(self.turn), micro_batch):
                if not self._check_memory():
                    print(f"⚠️ Memory pressure at {i}/{len(self.turn)}")
                    gc.collect()
                    time.sleep(2)
                
                batch_end = min(i + micro_batch, len(self.turn))
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
                    
                    batch_data.append(dist)
                
                # Partial fit on batch
                if batch_data:
                    X_batch = np.array(batch_data)
                    kmeans.partial_fit(X_batch)
                    del X_batch, batch_data
                
                # Checkpoint every 100 combinations
                if (i - start_idx) % 100 == 0:
                    self._save_stage_checkpoint('turn', i + len(batch), kmeans)
                    gc.collect()
                    
                    memory_usage = self._get_memory_usage_gb()
                    pbar.set_postfix(memory=f"{memory_usage:.1f}GB")
                
                self.conn.commit()
                pbar.update(len(batch))
        
        # Phase 2: Assign cluster labels
        self._assign_turn_clusters(kmeans)
        
        # Finalize
        self._finalize_turn_clusters()
        print(f"✅ Turn clustering complete. Memory: {self._get_memory_usage_gb():.1f}GB")
    
    def _assign_turn_clusters(self, kmeans):
        """Assign cluster labels to turn combinations."""
        print("Assigning turn cluster labels...")
        
        with tqdm(total=len(self.turn), desc="Assigning clusters") as pbar:
            for i in range(0, len(self.turn), self.batch_size * 2):
                batch_end = min(i + self.batch_size * 2, len(self.turn))
                
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
                    
                    del X_batch, batch_data
                
                self.conn.commit()
                gc.collect()
                pbar.update(batch_end - i)
        
        # Save centroids
        self.turn_centroids = kmeans.cluster_centers_
        self._save_stage_checkpoint('turn', len(self.turn), kmeans, self.turn_centroids)
    
    def _finalize_turn_clusters(self):
        """Build final turn lookup table from database."""
        turn_lut = {}
        cursor = self.conn.execute('''
            SELECT combo_id, combo_cards, cluster_id 
            FROM turn_data 
            ORDER BY combo_id
        ''')
        
        for row in cursor:
            combo = pickle.loads(row[1])
            cluster_id = row[2]
            turn_lut[tuple(combo)] = cluster_id
        
        self.card_info_lut["turn"] = turn_lut
        
        # Save checkpoint
        checkpoint_path = self.checkpoint_dir / "checkpoint_turn.joblib"
        joblib.dump({
            "turn": self.turn,
            "centroids": self.turn_centroids if hasattr(self, 'turn_centroids') else None
        }, checkpoint_path, compress=3)
    
    def cluster_flop(self):
        """Process flop stage with SQLite backing."""
        print("\n" + "="*60)
        print("FLOP STAGE - SQLite Backed Processing")
        print("="*60)
        
        # Check for checkpoint
        checkpoint = self._load_stage_checkpoint('flop')
        start_idx = 0
        kmeans = None
        
        if checkpoint:
            start_idx = checkpoint['last_processed_index']
            kmeans = checkpoint['kmeans']
            print(f"📂 Resuming from index {start_idx}/{len(self.flop)}")
        
        if start_idx >= len(self.flop):
            print("✅ Flop stage already complete")
            self._finalize_flop_clusters()
            return
        
        # Initialize MiniBatchKMeans
        if kmeans is None:
            kmeans = MiniBatchKMeans(
                n_clusters=self.n_flop_clusters,
                batch_size=min(500, self.batch_size * 5),
                n_init=3,
                max_iter=100,
                random_state=42,
                verbose=0
            )
        
        print(f"Processing {len(self.flop)} flop combinations...")
        
        # Phase 1: Process and store flop distributions
        with tqdm(total=len(self.flop) - start_idx, 
                  desc="Computing flop distributions") as pbar:
            
            for i in range(start_idx, len(self.flop), self.batch_size):
                batch_end = min(i + self.batch_size, len(self.flop))
                batch = self.flop[i:batch_end]
                
                batch_data = []
                for j, combo in enumerate(batch):
                    combo_id = i + j
                    
                    # Check if already processed
                    cursor = self.conn.execute(
                        'SELECT distribution FROM flop_data WHERE combo_id = ?',
                        (combo_id,)
                    )
                    row = cursor.fetchone()
                    
                    if row and row[0]:
                        dist = self._decompress_data(row[0])
                    else:
                        # Process new combination
                        dist = self.process_flop_potential_aware_distributions(combo)
                        
                        # Store in database with compression
                        self.conn.execute('''
                            INSERT OR REPLACE INTO flop_data 
                            (combo_id, combo_cards, distribution)
                            VALUES (?, ?, ?)
                        ''', (combo_id, pickle.dumps(combo), self._compress_data(dist)))
                    
                    batch_data.append(dist)
                
                # Partial fit on batch
                if batch_data:
                    X_batch = np.array(batch_data)
                    kmeans.partial_fit(X_batch)
                    del X_batch, batch_data
                
                # Checkpoint every 500 combinations
                if (i - start_idx) % 500 == 0:
                    self._save_stage_checkpoint('flop', i + len(batch), kmeans)
                    gc.collect()
                    
                    memory_usage = self._get_memory_usage_gb()
                    pbar.set_postfix(memory=f"{memory_usage:.1f}GB")
                
                self.conn.commit()
                pbar.update(len(batch))
        
        # Phase 2: Assign cluster labels
        self._assign_flop_clusters(kmeans)
        
        # Finalize
        self._finalize_flop_clusters()
        print(f"✅ Flop clustering complete. Memory: {self._get_memory_usage_gb():.1f}GB")
    
    def _assign_flop_clusters(self, kmeans):
        """Assign cluster labels to flop combinations."""
        print("Assigning flop cluster labels...")
        
        with tqdm(total=len(self.flop), desc="Assigning clusters") as pbar:
            for i in range(0, len(self.flop), self.batch_size * 5):
                batch_end = min(i + self.batch_size * 5, len(self.flop))
                
                # Load batch from database
                cursor = self.conn.execute('''
                    SELECT combo_id, distribution 
                    FROM flop_data 
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
                            'UPDATE flop_data SET cluster_id = ? WHERE combo_id = ?',
                            (int(label), combo_id)
                        )
                    
                    del X_batch, batch_data
                
                self.conn.commit()
                gc.collect()
                pbar.update(batch_end - i)
        
        # Save centroids
        self.flop_centroids = kmeans.cluster_centers_
        self._save_stage_checkpoint('flop', len(self.flop), kmeans, self.flop_centroids)
    
    def _finalize_flop_clusters(self):
        """Build final flop lookup table from database."""
        flop_lut = {}
        cursor = self.conn.execute('''
            SELECT combo_id, combo_cards, cluster_id 
            FROM flop_data 
            ORDER BY combo_id
        ''')
        
        for row in cursor:
            combo = pickle.loads(row[1])
            cluster_id = row[2]
            flop_lut[tuple(combo)] = cluster_id
        
        self.card_info_lut["flop"] = flop_lut
        
        # Save checkpoint
        checkpoint_path = self.checkpoint_dir / "checkpoint_flop.joblib"
        joblib.dump({
            "flop": self.flop,
            "centroids": self.flop_centroids if hasattr(self, 'flop_centroids') else None
        }, checkpoint_path, compress=3)
    
    def cluster_preflop(self):
        """Handle preflop clustering using lossless abstraction (no database needed)."""
        from poker_ai.clustering.preflop import compute_preflop_lossless_abstraction
        
        print("\n" + "="*60)
        print("PREFLOP STAGE - Lossless Abstraction")
        print("="*60)
        
        self.card_info_lut["pre_flop"] = compute_preflop_lossless_abstraction(
            self.low_card_rank, self.high_card_rank
        )
        print("✅ Preflop clustering complete")
    
    def compute(self, n_river_clusters: int, n_turn_clusters: int, n_flop_clusters: int):
        """Main entry point for computing clusters with specified sizes."""
        self.n_river_clusters = n_river_clusters
        self.n_turn_clusters = n_turn_clusters
        self.n_flop_clusters = n_flop_clusters
        
        print(f"\nStarting unified SQLite-backed clustering")
        print(f"River clusters: {n_river_clusters}")
        print(f"Turn clusters: {n_turn_clusters}")
        print(f"Flop clusters: {n_flop_clusters}")
        print(f"Database: {self.db_path}")
        print(f"Memory limit: {self.memory_limit_gb}GB")
        print(f"Initial memory: {self._get_memory_usage_gb():.1f}GB")
        
        # Process each stage
        stages = [
            ("preflop", self.cluster_preflop),
            ("river", self.cluster_river),
            ("turn", self.cluster_turn),
            ("flop", self.cluster_flop)
        ]
        
        for stage_name, stage_func in stages:
            try:
                stage_func()
                
                # Save LUT after each stage
                joblib.dump(self.card_info_lut, self.card_info_lut_path, compress=3)
                print(f"💾 Saved LUT after {stage_name}")
                
                # Force cleanup
                gc.collect()
                
            except Exception as e:
                print(f"❌ Error in {stage_name}: {e}")
                raise
        
        # Save centroids
        centroids_path = Path(self.card_info_lut_path).parent / "centroids.joblib"
        centroids = {}
        if hasattr(self, 'river_centroids'):
            centroids["river"] = self.river_centroids
        if hasattr(self, 'turn_centroids'):
            centroids["turn"] = self.turn_centroids
        if hasattr(self, 'flop_centroids'):
            centroids["flop"] = self.flop_centroids
        
        joblib.dump(centroids, centroids_path, compress=3)
        
        # Final report
        print("\n" + "="*60)
        print("✅ CLUSTERING COMPLETE!")
        print("="*60)
        print(f"Final memory: {self._get_memory_usage_gb():.1f}GB")
        print(f"LUT saved to: {self.card_info_lut_path}")
        print(f"Centroids saved to: {centroids_path}")
        print(f"Database size: {self.db_path.stat().st_size / (1024**3):.2f}GB")
        
        # Show cluster counts
        print("\nCluster Summary:")
        for stage in ["pre_flop", "river", "turn", "flop"]:
            if stage in self.card_info_lut:
                count = len(set(self.card_info_lut[stage].values()))
                print(f"  {stage}: {count} clusters")
    
    def cleanup(self):
        """Clean up database and temporary files."""
        if self.conn:
            self.conn.close()
        
        # Optionally remove database after successful completion
        if self.db_path.exists():
            print(f"Database {self.db_path} can be deleted to free {self.db_path.stat().st_size / (1024**3):.2f}GB")