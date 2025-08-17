# Storage and Memory Optimization for Poker AI

## Problem Summary

The original LUT generation was failing on systems with limited RAM:
- User's system: 32GB RAM total, ~9GB available
- Original high mode required 80GB+ memory (failing at 98% turn creation)
- No ability to resume after crashes
- All-at-once processing causing memory overflow

## Solution Implemented

### 1. Memory-Efficient LUT Builder
Created `poker_ai/clustering/memory_efficient_builder.py` with:
- **Streaming processing**: Processes data in configurable chunks
- **MiniBatchKMeans**: Memory-efficient clustering algorithm
- **Checkpoint system**: Saves progress after each stage
- **Memory monitoring**: Tracks and limits memory usage
- **Garbage collection**: Aggressive cleanup after each chunk

### 2. Adaptive Configuration Script
Created `generate_lut_memory_safe.sh` with modes:
- **Minimal (5GB)**: 50/50/50 clusters, 2 simulations
- **Low (8GB)**: 100/75/75 clusters, 3 simulations  
- **Medium (20GB)**: 150/100/100 clusters, 8 simulations
- **High (45GB)**: 300/200/200 clusters, 15 simulations
- **Ultra (50GB)**: 400/300/300 clusters, 20 simulations

### 3. System Diagnostics
Created `diagnose_memory.py` to:
- Analyze system memory availability
- Calculate dataset sizes
- Recommend optimal settings
- Identify memory bottlenecks

## Key Fixes Applied

1. **Import corrections**: Fixed class name from `CardInfoLUTBuilder` to `CardInfoLutBuilder`
2. **Constructor alignment**: Matched parent class signature with proper parameters
3. **Method name fixes**: Updated to use correct parent methods:
   - `process_river_ehs` instead of `process_river_distribution`
   - `process_turn_ehs_distributions` instead of `process_turn_potential_aware_distributions`
4. **Memory detection**: Fixed macOS memory detection in shell script
5. **Dependency installation**: Added required packages (psutil, tqdm, scikit-learn, joblib, click)
6. **Cluster mapping**: Fixed to use tuple keys matching parent implementation

## Usage Instructions

### Quick Start
```bash
# Auto-detect and use optimal settings
./generate_lut_memory_safe.sh auto

# Or explicitly choose a mode
./generate_lut_memory_safe.sh minimal  # 5GB limit
./generate_lut_memory_safe.sh low      # 8GB limit
```

### Monitor Progress
The script shows:
- Real-time progress bars for each stage
- Memory usage statistics
- Checkpoint saves after each stage
- Estimated time remaining

### Resume After Interruption
Simply run the same command again - it will automatically detect and load checkpoints:
```bash
./generate_lut_memory_safe.sh minimal  # Will resume from last checkpoint
```

## Performance Results

On a 32GB system with 9GB available:
- **Original**: Failed with memory overflow
- **Minimal mode**: Successfully runs within 5GB limit
- **Processing speed**: ~3.3 combinations/second
- **Estimated time**: 1-2 hours for minimal mode

## Technical Details

### Memory Breakdown (Minimal Mode)
- Preflop: < 100MB (lossless abstraction)
- River: ~500MB (50 clusters)
- Turn: ~1GB (50 clusters) 
- Flop: ~500MB (50 clusters)
- Overhead: ~2GB (Python, libraries, buffers)
- **Total**: < 5GB

### Checkpointing System
Saves after each stage:
- `lut_checkpoints/checkpoint_preflop.joblib`
- `lut_checkpoints/checkpoint_river.joblib`
- `lut_checkpoints/checkpoint_turn.joblib`
- `lut_checkpoints/checkpoint_flop.joblib`

### Output Files
- `card_info_lut.joblib`: Main lookup table
- `centroids.joblib`: Cluster centroids for each stage

## Recommendations

For systems with limited RAM:
1. **Close unnecessary applications** before running
2. **Start with minimal mode** to verify everything works
3. **Use checkpoint system** - you can interrupt and resume
4. **Monitor with diagnostic tool**: `python diagnose_memory.py`
5. **Consider cloud instances** for higher quality generation

## Future Improvements

1. **Dynamic memory adjustment**: Automatically reduce clusters if memory pressure detected
2. **Distributed processing**: Split across multiple machines
3. **Incremental clustering**: Build high-quality LUT in stages over multiple runs
4. **Compression**: Use compressed data structures to reduce memory footprint