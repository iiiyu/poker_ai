# Technical Decisions Log

## Database Choice for Turn Processing: SQLite vs RocksDB

### Decision: SQLite ✅

### Context
During LUT generation, the turn processing phase was crashing at 98% completion due to memory accumulation. We needed a database to store intermediate distributions (1326 combinations × 400-dimensional vectors).

### Options Considered

#### RocksDB
- **Pros:**
  - Optimized for key-value storage (LSM-tree architecture)
  - Better write performance (200-500 ops/sec)
  - Excellent compression ratios
  - Lower write amplification
  
- **Cons:**
  - Requires C++ compilation (complex on macOS)
  - External dependency (`python-rocksdb`)
  - Overkill for 1326 items
  - More complex configuration

#### SQLite (Chosen)
- **Pros:**
  - Built into Python standard library
  - Zero dependencies
  - Rock-solid crash recovery
  - Simple, well-documented API
  - Single-file storage
  
- **Cons:**
  - Slower for large-scale operations
  - Less optimized for BLOB storage

### Rationale for SQLite

1. **Scale**: We're storing only 1326 items, not millions where RocksDB excels
2. **Simplicity**: No compilation or dependency management needed
3. **Performance**: Database I/O is <1% of total time (bottleneck is computing distributions)
4. **Reliability**: SQLite's crash recovery is battle-tested
5. **Temporary Storage**: Database is deleted after processing completes

### Performance Optimizations Applied

```sql
PRAGMA journal_mode = WAL;      -- Write-ahead logging for concurrency
PRAGMA synchronous = NORMAL;    -- Faster writes (safe for temp data)
PRAGMA cache_size = -64000;      -- 64MB cache
PRAGMA temp_store = MEMORY;      -- Memory for temporary tables
PRAGMA mmap_size = 268435456;    -- 256MB memory-mapped I/O
```

### Results
- Database writes: ~15-30 seconds total
- Computing distributions: ~1.5 hours (the real bottleneck)
- Memory usage: Stays under 50GB limit
- Crash recovery: Can resume from exact position

### Conclusion
SQLite provides the perfect balance of simplicity, reliability, and performance for this use case. RocksDB would add complexity without meaningful performance gains at this scale.