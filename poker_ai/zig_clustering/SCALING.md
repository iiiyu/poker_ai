# Scaling Poker LUT Generation for More Coverage

## Current Limitations

The current implementation generates:
- **River**: 1,000 combinations (out of ~133 million possible)
- **Turn**: 180 combinations (out of ~2.8 million possible)
- **Flop**: 285 combinations (out of ~60,000 possible)

## Full Coverage Numbers

### River (7 cards total)
- **Full coverage**: C(52,2) × C(50,5) = 1,326 × 2,118,760 = **2,809,475,760** combinations
- **Practical subset**: ~1-10 million for good coverage

### Turn (6 cards total)  
- **Full coverage**: C(52,2) × C(50,4) = 1,326 × 230,300 = **305,377,800** combinations
- **Practical subset**: ~100k-1M for good coverage

### Flop (5 cards total)
- **Full coverage**: C(52,2) × C(50,3) = 1,326 × 19,600 = **25,989,600** combinations
- **Practical subset**: ~10k-100k for good coverage

## Scaling Strategies

### 1. Quick Configuration Change

Edit `src/main.zig` to increase limits:

```zig
// Configuration for clustering
const Config = struct {
    // Clustering parameters
    n_river_clusters: usize = 200,
    n_turn_clusters: usize = 200,
    n_flop_clusters: usize = 200,
    n_preflop_clusters: usize = 169,
    
    // Memory management
    chunk_size: usize = 100,  // Increase for better performance
    
    // Coverage limits (NEW)
    max_river_combos: usize = 10000,  // Increase these
    max_turn_combos: usize = 5000,
    max_flop_combos: usize = 5000,
    
    // Database
    db_path: []const u8 = "clustering_lut.db",
    
    // Mode
    emergency_mode: bool = false,
};
```

### 2. Progressive Coverage Modes

Add different coverage levels:

```zig
pub const CoverageMode = enum {
    Test,      // 1k combos (current)
    Light,     // 10k combos
    Medium,    // 100k combos  
    Heavy,     // 1M combos
    Full,      // All combos (warning: very slow)
};
```

### 3. Isomorphic Reduction

Reduce combinations by exploiting poker symmetries:

```zig
// Suits are interchangeable in many cases
// AhKs is strategically equivalent to AdKc
fn canonicalForm(hand: []Card, board: []Card) u64 {
    // Convert to suit-agnostic representation
    // This can reduce combinations by ~24x
}
```

### 4. Strategic Sampling

Instead of iterating through all combinations sequentially, sample strategically:

```zig
fn generateStrategicSample(self: *LUTBuilder, target_count: usize) ![]Combination {
    // 1. Generate all pocket pairs (high priority)
    // 2. Generate suited connectors
    // 3. Generate broadway hands
    // 4. Sample remaining hands uniformly
}
```

### 5. Resumable Processing

For very large datasets, implement checkpointing:

```zig
fn saveProgress(self: *LUTBuilder, stage: []const u8, last_combo: usize) !void {
    try self.storage.saveCheckpoint(stage, @intCast(last_combo), null, null);
}

fn resumeFromCheckpoint(self: *LUTBuilder, stage: []const u8) !usize {
    // Query checkpoint table and resume from last position
}
```

## Implementation Examples

### Example 1: Increase Coverage to 100k River Combinations

```zig
// In src/lut_builder.zig
fn generateRiverCombinations(self: *LUTBuilder) ![]Combination {
    var combos = std.ArrayList(Combination).init(self.allocator);
    
    const max_combos = 100000; // Increased from 1000
    const skip_factor = 28; // Sample every 28th combination
    
    var count: usize = 0;
    var skip_counter: usize = 0;
    
    // Generate hand combinations
    var i: usize = 0;
    while (i < self.all_cards.len - 1 and count < max_combos) : (i += 1) {
        var j = i + 1;
        while (j < self.all_cards.len and count < max_combos) : (j += 1) {
            // Skip some combinations for uniform sampling
            skip_counter += 1;
            if (skip_counter % skip_factor != 0) continue;
            
            // ... rest of generation code
        }
    }
}
```

### Example 2: Memory-Efficient Batch Processing

```zig
pub fn buildRiverLUTBatched(self: *LUTBuilder, batch_size: usize) !void {
    const total_target = 1000000;
    var processed: usize = 0;
    
    while (processed < total_target) {
        const batch_end = @min(processed + batch_size, total_target);
        
        // Generate batch
        const combos = try self.generateRiverCombinationsBatch(
            processed, 
            batch_end
        );
        defer self.allocator.free(combos);
        
        // Process batch
        for (combos) |combo| {
            // Calculate EHS and store
        }
        
        // Flush to disk
        try self.storage.flush();
        
        processed = batch_end;
        std.debug.print("Processed {}/{} river combos\n", .{processed, total_target});
    }
}
```

## Recommended Approach

1. **Start with Medium Coverage** (100k-1M combos per stage)
2. **Use Strategic Sampling** to ensure diverse hand coverage
3. **Implement Batch Processing** to manage memory
4. **Add Progress Saving** for long-running computations
5. **Consider Isomorphic Reduction** for maximum efficiency

## Memory Requirements

| Coverage | River Memory | Turn Memory | Flop Memory | Total |
|----------|-------------|-------------|-------------|--------|
| Test (1k) | ~10 MB | ~5 MB | ~5 MB | ~20 MB |
| Light (10k) | ~100 MB | ~50 MB | ~50 MB | ~200 MB |
| Medium (100k) | ~1 GB | ~500 MB | ~500 MB | ~2 GB |
| Heavy (1M) | ~10 GB | ~5 GB | ~5 GB | ~20 GB |
| Full | ~100+ GB | ~30 GB | ~2 GB | ~130+ GB |

## Next Steps

1. Choose your target coverage level
2. Update the configuration in `src/main.zig`
3. Modify the generator functions in `src/lut_builder.zig`
4. Run with appropriate memory allocation
5. Monitor progress and adjust as needed