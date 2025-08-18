"""Centralized memory management for clustering operations."""

import gc
import os
import psutil
import time
from typing import Optional


class MemoryManager:
    """Manages memory usage and provides emergency cleanup procedures."""
    
    def __init__(self, memory_limit_gb: float = 50.0, 
                 safety_factor: float = 0.7,
                 aggressive_gc: bool = True):
        """
        Initialize memory manager.
        
        Args:
            memory_limit_gb: Maximum memory usage in gigabytes
            safety_factor: Use only this fraction of memory_limit_gb
            aggressive_gc: Whether to run garbage collection aggressively
        """
        self.memory_limit_gb = memory_limit_gb
        self.safety_factor = safety_factor
        self.effective_limit_gb = memory_limit_gb * safety_factor
        self.aggressive_gc = aggressive_gc
        
        # Track memory statistics
        self.peak_memory_gb = 0.0
        self.last_gc_time = time.time()
        self.gc_interval = 30  # seconds between forced GC
    
    def get_memory_usage_gb(self) -> float:
        """Get current memory usage in GB."""
        process = psutil.Process(os.getpid())
        memory_bytes = process.memory_info().rss
        memory_gb = memory_bytes / (1024 ** 3)
        
        # Update peak memory
        self.peak_memory_gb = max(self.peak_memory_gb, memory_gb)
        
        return memory_gb
    
    def check_memory(self) -> bool:
        """
        Check if we're within safe memory limits.
        
        Returns:
            True if within limits, False if over limit
        """
        current_usage = self.get_memory_usage_gb()
        
        if current_usage > self.effective_limit_gb:
            print(f"⚠️ Memory usage {current_usage:.1f}GB exceeds safe limit {self.effective_limit_gb:.1f}GB")
            return False
        
        return True
    
    def emergency_cleanup(self, wait_time: int = 5):
        """
        Perform emergency memory cleanup.
        
        Args:
            wait_time: Seconds to wait after cleanup
        """
        print("🚨 Emergency memory cleanup initiated...")
        
        # Force garbage collection
        collected = gc.collect(2)  # Most thorough collection
        print(f"  Collected {collected} objects")
        
        # Clear caches
        try:
            import sklearn.utils._cython_blas
            sklearn.utils._cython_blas._clear_cache()
        except:
            pass
        
        # Wait for memory to be released
        time.sleep(wait_time)
        
        # Report new memory usage
        new_usage = self.get_memory_usage_gb()
        print(f"  Memory after cleanup: {new_usage:.1f}GB")
    
    def periodic_gc(self):
        """Run garbage collection periodically if aggressive_gc is enabled."""
        if not self.aggressive_gc:
            return
        
        current_time = time.time()
        if current_time - self.last_gc_time > self.gc_interval:
            gc.collect()
            self.last_gc_time = current_time
    
    def wait_for_memory(self, target_gb: Optional[float] = None, 
                       max_wait: int = 60) -> bool:
        """
        Wait for memory usage to drop below target.
        
        Args:
            target_gb: Target memory usage (defaults to effective limit)
            max_wait: Maximum seconds to wait
            
        Returns:
            True if target reached, False if timeout
        """
        if target_gb is None:
            target_gb = self.effective_limit_gb
        
        start_time = time.time()
        while time.time() - start_time < max_wait:
            current = self.get_memory_usage_gb()
            if current < target_gb:
                return True
            
            print(f"Waiting for memory to drop below {target_gb:.1f}GB (current: {current:.1f}GB)...")
            self.emergency_cleanup(wait_time=2)
        
        return False
    
    def get_safe_batch_size(self, item_size_mb: float, 
                           min_batch: int = 1, 
                           max_batch: int = 100) -> int:
        """
        Calculate safe batch size based on available memory.
        
        Args:
            item_size_mb: Estimated size of one item in megabytes
            min_batch: Minimum batch size
            max_batch: Maximum batch size
            
        Returns:
            Safe batch size
        """
        current_usage = self.get_memory_usage_gb()
        available_gb = max(0, self.effective_limit_gb - current_usage)
        available_mb = available_gb * 1024
        
        # Calculate batch size with safety margin
        safe_batch = int(available_mb / item_size_mb * 0.5)  # Use only 50% of available
        
        return max(min_batch, min(safe_batch, max_batch))
    
    def report_status(self):
        """Print memory status report."""
        current = self.get_memory_usage_gb()
        percent = (current / self.effective_limit_gb) * 100
        
        status = "✅" if percent < 70 else "⚠️" if percent < 90 else "🚨"
        
        print(f"\n{status} Memory Status:")
        print(f"  Current: {current:.1f}GB ({percent:.0f}%)")
        print(f"  Peak: {self.peak_memory_gb:.1f}GB")
        print(f"  Limit: {self.effective_limit_gb:.1f}GB")
    
    def __enter__(self):
        """Context manager entry."""
        self.start_memory = self.get_memory_usage_gb()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        if self.aggressive_gc:
            gc.collect()
        
        # Report memory delta
        end_memory = self.get_memory_usage_gb()
        delta = end_memory - self.start_memory
        if abs(delta) > 0.1:  # Only report significant changes
            print(f"Memory delta: {delta:+.1f}GB")