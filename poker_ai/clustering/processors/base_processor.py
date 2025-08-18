"""Base processor with common functionality for all stages."""

from abc import ABC, abstractmethod
from typing import List, Optional, Tuple
import numpy as np
from sklearn.cluster import MiniBatchKMeans
from tqdm import tqdm

from ..core import StorageBackend, MemoryManager


class BaseProcessor(ABC):
    """Abstract base class for stage processors."""
    
    def __init__(self, 
                 storage: StorageBackend,
                 memory_manager: MemoryManager,
                 n_clusters: int,
                 batch_size: int = 50):
        """
        Initialize base processor.
        
        Args:
            storage: Storage backend instance
            memory_manager: Memory manager instance
            n_clusters: Number of clusters for this stage
            batch_size: Processing batch size
        """
        self.storage = storage
        self.memory = memory_manager
        self.n_clusters = n_clusters
        self.batch_size = batch_size
        self.stage_name = self.__class__.__name__.replace('Processor', '').lower()
    
    @abstractmethod
    def compute_distribution(self, combo: np.ndarray) -> np.ndarray:
        """
        Compute distribution for a single combination.
        
        Args:
            combo: Card combination
            
        Returns:
            Distribution array
        """
        pass
    
    def process_streaming(self, combinations: List[np.ndarray], 
                         resume_from: int = 0) -> MiniBatchKMeans:
        """
        Process combinations in streaming fashion with memory safety.
        
        Args:
            combinations: List of card combinations to process
            resume_from: Index to resume from (for checkpointing)
            
        Returns:
            Fitted KMeans model
        """
        # Load or initialize KMeans
        checkpoint = self.storage.load_checkpoint(self.stage_name)
        kmeans = None
        
        if checkpoint and checkpoint['kmeans']:
            kmeans = checkpoint['kmeans']
            resume_from = checkpoint['last_processed_index']
            print(f"Resuming {self.stage_name} from index {resume_from}")
        
        if kmeans is None:
            kmeans = MiniBatchKMeans(
                n_clusters=self.n_clusters,
                batch_size=min(200, self.batch_size * 4),
                n_init=3,
                max_iter=100,
                random_state=42,
                verbose=0
            )
        
        # Calculate safe batch size based on available memory
        safe_batch = self.memory.get_safe_batch_size(
            item_size_mb=2.0,  # Estimated size per distribution
            min_batch=5,
            max_batch=self.batch_size
        )
        
        print(f"Processing {len(combinations)} {self.stage_name} combinations")
        print(f"Batch size: {safe_batch}, Chunk size: {self.storage.chunk_size}")
        
        # Process combinations
        with tqdm(total=len(combinations) - resume_from, 
                 desc=f"Computing {self.stage_name} distributions") as pbar:
            
            for i in range(resume_from, len(combinations), safe_batch):
                # Memory check
                if not self.memory.check_memory():
                    self.memory.emergency_cleanup()
                    
                    # Recalculate safe batch size
                    safe_batch = self.memory.get_safe_batch_size(
                        item_size_mb=2.0,
                        min_batch=5,
                        max_batch=self.batch_size
                    )
                
                batch_end = min(i + safe_batch, len(combinations))
                batch = combinations[i:batch_end]
                
                batch_data = []
                for j, combo in enumerate(batch):
                    combo_id = i + j
                    
                    # Check if already processed
                    existing = self.storage.get_distribution(self.stage_name, combo_id)
                    
                    if existing is not None:
                        dist = existing
                    else:
                        # Compute new distribution
                        dist = self.compute_distribution(combo)
                        
                        # Store immediately
                        self.storage.store_distribution(
                            self.stage_name, combo_id, combo, dist
                        )
                    
                    batch_data.append(dist)
                
                # Partial fit KMeans
                if batch_data:
                    X_batch = np.array(batch_data)
                    kmeans.partial_fit(X_batch)
                    del X_batch
                    del batch_data
                
                # Periodic checkpoint
                if (i - resume_from) % 100 == 0:
                    self.storage.save_checkpoint(self.stage_name, i + len(batch), kmeans)
                    self.memory.periodic_gc()
                
                pbar.update(len(batch))
                pbar.set_postfix(memory=f"{self.memory.get_memory_usage_gb():.1f}GB")
        
        # Final checkpoint
        self.storage.save_checkpoint(
            self.stage_name, 
            len(combinations), 
            kmeans, 
            kmeans.cluster_centers_
        )
        
        return kmeans
    
    def assign_clusters_streaming(self, kmeans: MiniBatchKMeans, 
                                 combinations: List[np.ndarray]):
        """
        Assign cluster labels in streaming fashion.
        
        Args:
            kmeans: Fitted KMeans model
            combinations: List of combinations
        """
        print(f"Assigning {self.stage_name} cluster labels...")
        
        safe_batch = min(self.storage.chunk_size, 10)
        
        with tqdm(total=len(combinations), desc="Assigning clusters") as pbar:
            for i in range(0, len(combinations), safe_batch):
                # Memory check
                if not self.memory.check_memory():
                    self.memory.emergency_cleanup()
                
                batch_end = min(i + safe_batch, len(combinations))
                
                # Get distributions from storage
                batch_data = self.storage.get_batch_distributions(
                    self.stage_name, i, batch_end
                )
                
                if batch_data:
                    combo_ids = [cid for cid, _ in batch_data]
                    distributions = [dist for _, dist in batch_data]
                    
                    # Predict clusters
                    X_batch = np.array(distributions)
                    labels = kmeans.predict(X_batch)
                    
                    # Update storage
                    updates = [(int(label), combo_id) 
                              for combo_id, label in zip(combo_ids, labels)]
                    self.storage.update_cluster_ids(self.stage_name, updates)
                    
                    del X_batch
                    del distributions
                
                self.memory.periodic_gc()
                pbar.update(batch_end - i)
    
    def build_lut_streaming(self) -> dict:
        """
        Build lookup table by streaming from database.
        
        Returns:
            Dictionary mapping card combinations to cluster IDs
        """
        print(f"Building {self.stage_name} LUT...")
        
        lut = {}
        count = 0
        
        for combo, cluster_id in self.storage.stream_clusters(self.stage_name):
            lut[tuple(combo)] = cluster_id
            count += 1
            
            # Periodic memory check
            if count % 1000 == 0:
                if not self.memory.check_memory():
                    # Save partial LUT and clear
                    print(f"Memory pressure - saving partial LUT ({count} entries)")
                    partial_lut = lut.copy()
                    lut.clear()
                    yield partial_lut
        
        # Return final LUT
        if lut:
            yield lut