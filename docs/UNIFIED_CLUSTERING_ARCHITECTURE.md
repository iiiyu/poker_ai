# Unified SQLite Clustering Architecture

## Executive Summary

This document describes the comprehensive SQLite-backed clustering architecture that solves memory overflow issues across all clustering stages (river, turn, flop) in the poker AI system.

## Problem Statement

The original clustering system had several critical issues:

1. **Memory Overflow**: Turn and flop stages accumulated 100+ MB of data in memory, causing crashes
2. **Inconsistent Implementation**: Only turn had SQLite backing via `IncrementalTurnProcessor`
3. **Fragmented Architecture**: Multiple inheritance chains with different approaches
4. **No Unified Recovery**: Each stage had different checkpoint/resume mechanisms

## Solution Architecture

### Core Design Principles

1. **Consistency**: All stages use the same SQLite-backed approach
2. **Streaming**: Data is streamed from database, never fully loaded into memory
3. **Atomicity**: Each combination is processed and immediately persisted
4. **Resumability**: Every stage supports checkpoint/resume at any point
5. **Modularity**: Stage-specific logic is encapsulated in processor classes

### System Components

```
UnifiedSQLiteLUTBuilder
├── Database Layer (SQLite)
│   ├── river_distributions (3D vectors)
│   ├── turn_distributions (400D compressed)
│   ├── flop_distributions (400D compressed)
│   ├── centroids (all stages)
│   └── clustering_progress (tracking)
│
├── Stage Processors
│   ├── RiverProcessor (3D EHS vectors)
│   ├── TurnProcessor (400D distributions)
│   └── FlopProcessor (400D distributions)
│
└── Clustering Engine
    ├── MiniBatchKMeans (streaming)
    └── Incremental updates
```

## Database Schema

### Master Tables

```sql
-- Progress tracking
clustering_progress
├── stage (PRIMARY KEY)
├── total_combinations
├── processed_combinations
├── status (pending|processing|completed)
└── timestamps

-- Centroids storage
centroids
├── stage
├── cluster_id
└── centroid_data (BLOB - pickled numpy array)
```

### Stage-Specific Tables

#### River (3D vectors - uncompressed)
```sql
river_distributions
├── combo_id (PRIMARY KEY)
├── hole_cards (2 columns)
├── board_cards (5 columns)
├── win_rate, loss_rate, tie_rate (REAL)
└── cluster_id (INTEGER)
```

#### Turn (400D distributions - compressed)
```sql
turn_distributions
├── combo_id (PRIMARY KEY)
├── hole_cards (2 columns)
├── board_cards (4 columns)
├── distribution (BLOB - zlib compressed)
└── cluster_id (INTEGER)
```

#### Flop (400D distributions - compressed)
```sql
flop_distributions
├── combo_id (PRIMARY KEY)
├── hole_cards (2 columns)
├── board_cards (3 columns)
├── distribution (BLOB - zlib compressed)
└── cluster_id (INTEGER)
```

## Data Flow

### Processing Pipeline

```
1. INITIALIZATION
   ├── Create/connect to SQLite database
   ├── Set performance pragmas (WAL, cache, mmap)
   └── Load any existing progress

2. RIVER STAGE (77,520 combinations)
   ├── Process in batches of 100
   ├── Each combo → 3D vector (win/loss/tie)
   ├── Store directly in database
   └── Stream clustering with MiniBatchKMeans

3. TURN STAGE (38,760 combinations)
   ├── Requires river centroids
   ├── Process in micro-batches of 20
   ├── Each combo → 400D distribution
   ├── Compress with zlib before storing
   └── Stream clustering from database

4. FLOP STAGE (15,504 combinations)
   ├── Requires turn centroids
   ├── Process in batches of 50
   ├── Each combo → 400D distribution
   ├── Compress with zlib before storing
   └── Stream clustering from database

5. FINALIZATION
   ├── Build lookup tables from database
   ├── Export to joblib format
   └── Clean up temporary data
```

### Memory Management

```python
Memory Usage by Stage:
├── River: ~2MB in memory at any time
├── Turn: ~6MB in memory (20 combos × 400D × 8 bytes)
├── Flop: ~15MB in memory (50 combos × 400D × 8 bytes)
└── Database: All data persisted immediately

Optimization Techniques:
├── Micro-batching for large vectors
├── zlib compression for 400D distributions
├── Streaming clustering (never load all data)
├── Aggressive garbage collection
└── Memory monitoring with auto-cleanup
```

## Implementation Details

### Key Classes

#### UnifiedSQLiteLUTBuilder
- Main orchestrator class
- Manages database connection and transactions
- Coordinates stage processing
- Handles checkpointing and recovery

#### StageProcessor (Abstract)
- Base class for stage-specific logic
- Methods: `process_combination()`, `store_vector()`, `retrieve_vectors()`
- Inherited by River/Turn/FlopProcessor

#### StreamingClusterer
- Generic clustering with database backing
- Uses MiniBatchKMeans for incremental learning
- Streams data in configurable batches

### Performance Optimizations

1. **Database Optimizations**
   ```sql
   PRAGMA journal_mode = WAL;      -- Write-ahead logging
   PRAGMA synchronous = NORMAL;    -- Faster writes
   PRAGMA cache_size = -64000;     -- 64MB cache
   PRAGMA temp_store = MEMORY;     -- Memory for temp tables
   PRAGMA mmap_size = 268435456;   -- 256MB memory-mapped I/O
   ```

2. **Compression Strategy**
   - River: No compression (only 3 floats)
   - Turn/Flop: zlib compression (400 floats → ~40% size)
   - Compression ratio: ~60% reduction

3. **Batch Sizing**
   - River: 100 combinations (optimal for 3D vectors)
   - Turn: 20 combinations (memory-constrained)
   - Flop: 50 combinations (balanced approach)

## Migration Path

### From Current System

1. **Backup Phase**
   ```bash
   python migrate_to_unified.py
   ```
   - Backs up existing checkpoints
   - Backs up existing databases
   - Preserves all LUT files

2. **Migration Phase**
   - Extracts centroids from old checkpoints
   - Converts IncrementalTurnProcessor database
   - Migrates to unified schema

3. **Verification Phase**
   - Validates centroid counts
   - Checks distribution counts
   - Ensures data integrity

### Code Changes Required

```python
# Old approach (multiple classes)
from poker_ai.clustering.memory_efficient_builder import MemoryEfficientLUTBuilder
from poker_ai.clustering.incremental_turn_processor import IncrementalTurnProcessor

# New approach (single unified class)
from poker_ai.clustering.unified_sqlite_builder import UnifiedSQLiteLUTBuilder

builder = UnifiedSQLiteLUTBuilder(
    low_card_rank=10,
    high_card_rank=14,
    db_path=Path("clustering.db"),
    memory_limit_gb=4.0
)

builder.build(
    n_river_clusters=200,
    n_turn_clusters=400,
    n_flop_clusters=400
)
```

## Risk Assessment

### Identified Risks

1. **Database Size**
   - Estimated: 200-500 MB for 20-card deck
   - Mitigation: Compression, cleanup after clustering

2. **I/O Performance**
   - Risk: Slower than in-memory processing
   - Mitigation: WAL mode, memory-mapped I/O, batching

3. **Clustering Quality**
   - Risk: MiniBatchKMeans vs full KMeans
   - Mitigation: Multiple passes, larger batch sizes

### Mitigation Strategies

1. **Checkpoint Recovery**
   - Automatic resume from any failure point
   - No data loss on crashes

2. **Memory Monitoring**
   - Real-time memory usage tracking
   - Automatic garbage collection triggers

3. **Progress Tracking**
   - Database-level progress persistence
   - Stage-level completion markers

## Performance Metrics

### Expected Performance (20-card deck)

| Stage | Combinations | Processing Time | Memory Peak | Database Size |
|-------|-------------|-----------------|-------------|---------------|
| River | 77,520 | ~15 minutes | <500 MB | 6 MB |
| Turn | 38,760 | ~45 minutes | <1 GB | 60 MB |
| Flop | 15,504 | ~30 minutes | <800 MB | 24 MB |
| **Total** | **131,784** | **~90 minutes** | **<1 GB** | **~90 MB** |

### Scalability to 52-card deck

| Stage | Combinations | Est. Time | Database Size |
|-------|-------------|-----------|---------------|
| River | 133,784,560 | ~20 hours | 10 GB |
| Turn | 25,989,600 | ~30 hours | 40 GB |
| Flop | 2,598,960 | ~10 hours | 4 GB |

## Testing Strategy

### Unit Tests
```python
# Test individual processors
test_river_processor_vector_generation()
test_turn_processor_distribution()
test_flop_processor_compression()

# Test database operations
test_sqlite_initialization()
test_checkpoint_recovery()
test_streaming_retrieval()
```

### Integration Tests
```python
# Test full pipeline
test_mini_dataset_clustering()  # 100 combos per stage
test_checkpoint_resume()        # Kill and resume
test_memory_limits()           # Enforce 512MB limit
```

### Performance Tests
```python
# Benchmark operations
benchmark_compression_speed()
benchmark_database_writes()
benchmark_streaming_clustering()
```

## Monitoring and Debugging

### Key Metrics to Monitor

1. **Memory Usage**
   ```python
   process = psutil.Process(os.getpid())
   memory_gb = process.memory_info().rss / 1024**3
   ```

2. **Database Size**
   ```sql
   SELECT 
     COUNT(*) as total_rows,
     SUM(LENGTH(distribution)) / 1024.0 / 1024.0 as size_mb
   FROM turn_distributions;
   ```

3. **Processing Rate**
   ```python
   combinations_per_second = processed / elapsed_time
   estimated_completion = remaining / combinations_per_second
   ```

### Debug Tools

```python
# Check stage progress
python -c "from unified_sqlite_builder import check_progress; check_progress()"

# Verify database integrity
python -c "from unified_sqlite_builder import verify_database; verify_database()"

# Export statistics
python -c "from unified_sqlite_builder import export_stats; export_stats()"
```

## Conclusion

The unified SQLite-backed architecture provides:

1. **Reliability**: No memory overflows at any stage
2. **Consistency**: Same approach for all stages
3. **Resumability**: Full checkpoint/resume support
4. **Scalability**: Works for both 20-card and 52-card decks
5. **Maintainability**: Single codebase, clear abstractions

This architecture solves all identified issues while maintaining clustering quality and providing a clear migration path from the existing system.