# Migration Guide: Unified LUT Builder

## Overview

The poker_ai clustering module has been refactored from 6 redundant implementations into a single, clean architecture. This guide helps you migrate from the old builders to the new `UnifiedLUTBuilder`.

## What Changed

### Old Architecture (DEPRECATED)
- `CardInfoLutBuilder` - Base implementation
- `CardInfoLutBuilderExtended` - Minor extension
- `MemoryEfficientLUTBuilder` - Chunk-based processing
- `UnifiedSQLiteLUTBuilder` - SQLite-backed processing  
- `MemorySafeUnifiedBuilder` - Memory-safe with streaming
- `MemorySafeBuilder` - Another memory variant

**Total: ~3900 lines of redundant code**

### New Architecture
```
poker_ai/clustering/
├── core/
│   ├── storage_backend.py    # Unified SQLite storage
│   └── memory_manager.py     # Centralized memory management
├── processors/
│   ├── base_processor.py     # Shared processing logic
│   ├── river_processor.py    # River stage
│   ├── turn_processor.py     # Turn stage (memory-critical)
│   └── flop_processor.py     # Flop stage
└── unified_builder.py        # Single entry point
```

**Total: ~800 lines of clean, maintainable code**

## Migration Steps

### 1. Update Your Imports

**Before:**
```python
from poker_ai.clustering.card_info_lut_builder import CardInfoLutBuilder
# or
from poker_ai.clustering.memory_safe_unified_builder import MemorySafeUnifiedBuilder
# or any other builder...
```

**After:**
```python
from poker_ai.clustering.unified_builder import UnifiedLUTBuilder
```

### 2. Update Your Code

**Before:**
```python
# Old way - multiple different builders
builder = CardInfoLutBuilder(
    n_simulations_river=100,
    n_simulations_turn=100,
    n_simulations_flop=100,
    low_card_rank=2,
    high_card_rank=14,
    save_dir="."
)
builder.compute(
    n_river_clusters=200,
    n_turn_clusters=200,
    n_flop_clusters=200
)
```

**After:**
```python
# New way - single unified builder
with UnifiedLUTBuilder(
    n_simulations_river=100,
    n_simulations_turn=100,
    n_simulations_flop=100,
    low_card_rank=2,
    high_card_rank=14,
    n_river_clusters=200,
    n_turn_clusters=200,
    n_flop_clusters=200,
    memory_limit_gb=50.0,      # New: explicit memory control
    chunk_size=10,              # New: automatic chunking
    save_dir="."
) as builder:
    builder.compute()
```

### 3. Update Shell Scripts

**Before:**
```bash
python3 -c "
from poker_ai.clustering.memory_safe_unified_builder import MemorySafeUnifiedBuilder
builder = MemorySafeUnifiedBuilder(...)
builder.compute(n_river_clusters=..., n_turn_clusters=..., n_flop_clusters=...)
"
```

**After:**
```bash
python3 -c "
from poker_ai.clustering.unified_builder import UnifiedLUTBuilder
builder = UnifiedLUTBuilder(...)  # All parameters in __init__
builder.compute()  # No parameters needed
"
```

## Key Improvements

### Memory Management
- **Automatic chunking**: Flushes to database every `chunk_size` items
- **Streaming processing**: Never loads all data at once
- **Emergency cleanup**: Automatic memory recovery when limits approached
- **Safe batch sizing**: Dynamic adjustment based on available memory

### Performance
- **3GB memory limit**: Can run on systems with limited RAM
- **Checkpoint/resume**: Automatic recovery from interruptions
- **Parallel processing**: Where safe to do so
- **SQLite optimization**: WAL mode, proper indexing

### Code Quality
- **Single source of truth**: One builder instead of 6
- **Clean separation**: Storage, memory, and processing concerns separated
- **Testable**: Each component can be tested independently
- **Maintainable**: 80% less code to maintain

## Configuration Options

### Memory Safety (Emergency Mode)
```python
builder = UnifiedLUTBuilder(
    memory_limit_gb=3.0,        # Strict 3GB limit
    memory_safety_factor=0.5,   # Use only 50% of limit
    chunk_size=10,              # Flush every 10 items
    batch_size=5,               # Process 5 at a time
    aggressive_gc=True          # Force garbage collection
)
```

### High Performance (Good Hardware)
```python
builder = UnifiedLUTBuilder(
    memory_limit_gb=50.0,       # 50GB available
    memory_safety_factor=0.8,   # Use 80% of limit
    chunk_size=100,             # Less frequent flushes
    batch_size=200,             # Large batches
    aggressive_gc=False         # Let Python manage GC
)
```

## Database Compatibility

The new builder uses the same SQLite schema as `UnifiedSQLiteLUTBuilder`, so existing databases are compatible. The checkpoint system also remains compatible.

## Files to Remove

After migration, these files can be safely deleted:
- `card_info_lut_builder.py`
- `card_info_lut_builder_extended.py`
- `memory_efficient_builder.py`
- `memory_safe_builder.py`
- `memory_safe_unified_builder.py`
- `unified_sqlite_builder.py`
- `incremental_turn_processor.py`
- `migrate_to_unified.py`

## Troubleshooting

### Out of Memory Errors
Reduce `chunk_size` and `batch_size`:
```python
builder = UnifiedLUTBuilder(..., chunk_size=5, batch_size=5)
```

### Slow Processing
Increase `batch_size` if memory allows:
```python
builder = UnifiedLUTBuilder(..., batch_size=100)
```

### Resume After Crash
The builder automatically resumes from checkpoints. Just run again with the same parameters.

## Support

For issues or questions about the migration, please check the existing database at `clustering_data.db` - it contains checkpoints that allow resuming from any interruption.