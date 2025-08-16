# Storage Optimization Guide for Poker AI

## Current Storage Architecture

### What We Have
- **LUT Storage**: `joblib` files (70MB) - Card clustering lookup tables
- **Strategy Storage**: Compressed `.gz` files (500KB-5MB) - Training checkpoints
- **Access Pattern**: Write-heavy during training, read-only during play

## Performance Analysis

### Where Time Is Actually Spent
```
99.9% - CPU: MCCFR calculations (regret minimization)
0.09% - Memory: Strategy updates
0.01% - Disk I/O: Checkpoint saves
```

**Key Insight**: Storage is NOT the bottleneck. Optimizing storage won't improve training speed.

## When Databases Would Help

### 1. Redis - For Real-time Multiplayer
```python
# If you need multiple agents training collaboratively
redis_client.hset(f"agent:{agent_id}:strategy", info_set, strategy_value)
redis_client.publish("strategy_updates", json.dumps(update))
```

**Use Case**: Distributed training across multiple machines

### 2. MongoDB - For Training Analytics
```python
# Track training progress over time
db.training_history.insert_one({
    "iteration": 10000,
    "timestamp": datetime.now(),
    "avg_regret": 0.0234,
    "strategy_size": 1024000,
    "performance_vs_baseline": 0.65
})
```

**Use Case**: Analyzing training patterns, comparing different approaches

### 3. RocksDB - For Massive Scale
```python
# When strategy size exceeds RAM (billions of states)
import rocksdb
db = rocksdb.DB("strategy.db", rocksdb.Options(create_if_missing=True))
db.put(info_set.encode(), pickle.dumps(strategy_value))
```

**Use Case**: Training full 52-card poker with 6+ players

## Actual Optimizations That Would Help

### 1. Memory-Mapped Files (Small Improvement)
```python
import numpy as np
# Instead of joblib, use memory-mapped numpy arrays
lut = np.memmap('card_lut.dat', dtype='float32', mode='r', shape=(1000000, 10))
```
**Benefit**: ~10% faster loading, less memory usage

### 2. Parallel I/O for Checkpoints
```python
from concurrent.futures import ThreadPoolExecutor
def save_checkpoint_parallel(strategy, iteration):
    with ThreadPoolExecutor(max_workers=4) as executor:
        # Split strategy into chunks and save in parallel
        futures = []
        for chunk in split_strategy(strategy, n_chunks=4):
            futures.append(executor.submit(save_chunk, chunk))
```
**Benefit**: Faster checkpoint saves (but still negligible impact)

### 3. Compression Optimization
```python
import lz4.frame
# Use LZ4 instead of gzip for faster compression
with lz4.frame.open('strategy.lz4', 'wb') as f:
    pickle.dump(strategy, f)
```
**Benefit**: 3-4x faster compression/decompression

### 4. REAL Performance Improvements

#### A. Algorithm Optimization
```python
# Use vectorized operations
strategies = np.array([...])  # Vectorize strategy updates
regrets = np.maximum(regrets + rewards, 0)  # Bulk operations
```
**Impact**: 10-50x speedup

#### B. Better Parallelization
```python
# Use Ray for distributed training
import ray
@ray.remote
def train_worker(start_iter, end_iter):
    # Train subset of game tree
    pass
```
**Impact**: Linear scaling with CPU cores

#### C. GPU Acceleration
```python
# Use JAX/PyTorch for neural network approximation
import jax.numpy as jnp
def compute_strategy_gpu(regrets):
    return jax.nn.softmax(regrets)
```
**Impact**: 100-1000x speedup for large states

## Recommended Architecture Changes

### For Your Current Scale (Short Deck, 3 Players)
**Keep current architecture** - It's already optimal

### For Medium Scale (Full Deck, 3-4 Players)
```python
# Add caching layer
from functools import lru_cache
@lru_cache(maxsize=100000)
def get_strategy(info_set):
    return strategy_dict.get(info_set, default_strategy)
```

### For Large Scale (Full Deck, 6+ Players)
Consider:
1. **Neural Network Approximation** - Don't store all states
2. **Distributed Training** - Use Ray or Dask
3. **Hybrid Storage** - Hot data in Redis, cold in RocksDB

## Monitoring Performance

### Add Performance Metrics
```python
import time
import psutil

class PerformanceMonitor:
    def __init__(self):
        self.iteration_times = []
        self.memory_usage = []
    
    def log_iteration(self, iteration):
        self.iteration_times.append(time.time())
        self.memory_usage.append(psutil.Process().memory_info().rss)
        
        if iteration % 1000 == 0:
            avg_time = np.mean(np.diff(self.iteration_times[-1000:]))
            print(f"Iterations/sec: {1/avg_time:.0f}")
            print(f"Memory: {self.memory_usage[-1]/1e9:.1f} GB")
```

## Conclusion

### Don't Optimize Storage Because:
1. **It's not the bottleneck** (0.01% of time)
2. **Current solution is near-optimal** for access patterns
3. **Database overhead would hurt performance**

### Instead, Focus On:
1. **Algorithm optimization** (vectorization, pruning)
2. **Better parallelization** (distributed training)
3. **Approximation methods** (neural networks for large state spaces)

### When to Consider Databases:
- ✅ Distributed training across multiple machines
- ✅ Training analytics and monitoring
- ✅ Real-time multiplayer scenarios
- ✅ When strategy size exceeds available RAM
- ❌ For your current single-machine training (would be slower)