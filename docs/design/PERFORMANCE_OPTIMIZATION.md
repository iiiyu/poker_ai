# Performance Optimization Guide

## Overview

This guide covers performance optimizations implemented in the poker AI system and how to achieve optimal training and clustering speeds.

## Recent Performance Improvements

### 1. Illegal Action Fix
**Problem**: Training crashed with "Action 'raise' not in legal actions" error  
**Solution**: Filter strategy by legal actions in CFR/CFRP functions  
**Impact**: Stable training without crashes

### 2. Clustering Progress Fix
**Problem**: Flop clustering appeared frozen at 0% for 10+ minutes  
**Solution**: Optimized chunk sizes for better parallelization  
**Impact**: Progress updates every 1-2 minutes instead of 10+

### 3. Training Speed Enhancements
**Problem**: Unrealistic time estimates (claimed 100 it/s)  
**Solution**: Accurate performance metrics and real-time monitoring  
**Impact**: Realistic expectations and better progress tracking

## Performance Benchmarks

### MCCFR Training Speed

| Configuration | Single Process | Multiprocess | 
|--------------|---------------|--------------|
| 2 players | ~15 it/s | ~40 it/s |
| 3 players | ~10 it/s | ~30 it/s |
| 4 players | ~7 it/s | ~20 it/s |
| 6 players | ~5 it/s | ~15 it/s |

### Clustering Performance

| Stage | Combinations | Time | Speed |
|-------|-------------|------|-------|
| River | 133M | ~5-10 min | ~300K/s |
| Turn | 20M | ~15-30 min | ~20K/s |
| Flop | 2.6M | ~1-3 hours | ~500/s |

## Optimization Strategies

### 1. For Training

**Use Multiprocessing**
```bash
./train_ai.sh medium --multi
```
- 2-3x speed improvement
- Requires more RAM (8GB+ recommended)
- Best for iterations > 1000

**Reduce Players**
```bash
./train_ai.sh medium --players 2 --multi
```
- 2 players is 3x faster than 6 players
- Good for initial strategy development

**Optimize Save Intervals**
```bash
python train_long_ai.py \
    --iterations 100000 \
    --save_interval 10000  # Save less frequently
```
- Reduces I/O overhead
- Balance between checkpointing and speed

### 2. For Clustering

**Optimize Worker Count**
```python
# Automatically optimized in card_info_lut_builder.py
n_workers = os.cpu_count() or 4
chunksize = max(1, min(100, len(data) // (n_workers * 10)))
```

**Memory Management**
- Close other applications
- Use system with 16GB+ RAM
- Monitor with: `python monitor_clustering.py`

### 3. System-Level Optimizations

**CPU Affinity** (Linux)
```bash
taskset -c 0-7 ./train_ai.sh medium --multi
```

**Nice Priority**
```bash
nice -n -10 ./train_ai.sh medium  # Higher priority
```

**Disable CPU Throttling** (Laptop)
- Set to performance mode
- Ensure adequate cooling
- Plug in power adapter

## Code-Level Optimizations

### 1. CFR Algorithm Optimizations

**Pruning Threshold**
```python
# In ai.py - prune branches with low regret
if this_info_sets_regret[action] > c:  # c = -20000
    # Explore this branch
```

**Linear CFR**
```python
# Discount old regrets after threshold
if t < lcfr_threshold and t % discount_interval == 0:
    d = (t / discount_interval) / ((t / discount_interval) + 1)
    agent.regret[I][a] *= d
```

### 2. State Representation Optimizations

**Info Set Caching**
```python
# State caches info set string
@property
def info_set(self) -> str:
    if not self._info_set_cache:
        self._info_set_cache = self._compute_info_set()
    return self._info_set_cache
```

**Card Clustering**
```python
# Reduces 10^14 combinations to manageable clusters
card_info_lut[stage][cards] = cluster_id
```

### 3. Memory Optimizations

**Strategy Compression**
```python
# Strategies saved as compressed .gz files
with gzip.open(f'strategy_{t}.gz', 'wb') as f:
    pickle.dump(strategy, f)
```

**Sparse Storage**
```python
# Only store non-zero regrets
if regret != 0:
    agent.regret[info_set][action] = regret
```

## Monitoring Tools

### Training Monitor
```bash
python monitor_training.py
```
- Real-time speed (it/s)
- ETA calculation
- Memory usage
- Strategy file size

### Clustering Monitor
```bash
python monitor_clustering.py
```
- Stage progress
- Time estimates
- CPU/Memory usage
- Completion predictions

### Performance Test
```bash
python test_training_speed.py
```
- Measures actual iteration speed
- Tests different player counts
- Provides recommendations

## Troubleshooting Performance Issues

### Slow Training

1. **Check CPU Usage**
   ```bash
   top  # or htop
   ```
   - Should be near 100% for single process
   - 100% * cores for multiprocess

2. **Check Memory**
   ```bash
   free -h  # Linux
   vm_stat  # macOS
   ```
   - Ensure no swapping
   - 8GB+ recommended

3. **Profile Code**
   ```bash
   python -m cProfile -o profile.out train_long_ai.py
   python -m pstats profile.out
   ```

### Memory Issues

1. **Reduce Batch Sizes**
   - Lower save_interval
   - Fewer players
   - Smaller clusters

2. **Clear Cache**
   ```python
   import gc
   gc.collect()
   ```

3. **Monitor Memory**
   ```bash
   watch -n 1 free -h
   ```

## Best Practices

### For Development
1. Use test mode LUT (fast generation)
2. Train with 2 players
3. Use small iteration counts
4. Single process for debugging

### For Production
1. Generate high-quality LUT
2. Use multiprocessing
3. Train with target player count
4. Monitor continuously
5. Use resume capability

### For Research
1. Track metrics carefully
2. Use consistent seeds
3. Document parameters
4. Version control strategies

## Future Optimization Opportunities

1. **GPU Acceleration**
   - Matrix operations in clustering
   - Parallel CFR traversal
   - Neural network integration

2. **Distributed Training**
   - Multi-machine coordination
   - Cloud scaling
   - Checkpoint synchronization

3. **Algorithm Improvements**
   - Monte Carlo sampling
   - Better pruning strategies
   - Adaptive clustering

4. **Storage Optimizations**
   - Better compression
   - Incremental saves
   - Database backend

## Summary

The system has been optimized for:
- **Stability**: No more illegal action crashes
- **Visibility**: Better progress reporting
- **Speed**: 2-3x improvement with multiprocessing
- **Accuracy**: Realistic time estimates
- **Monitoring**: Real-time performance tracking

For optimal performance:
1. Generate appropriate quality LUT
2. Use multiprocessing for training
3. Monitor progress continuously
4. Choose parameters based on use case
5. Have realistic time expectations