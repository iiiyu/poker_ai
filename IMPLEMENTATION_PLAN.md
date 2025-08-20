# Python to Zig Migration Implementation Plan

## Executive Summary

This plan outlines the systematic migration of the poker AI system from Python to Zig, targeting 10-100x performance improvements while maintaining algorithmic correctness.

**Key Targets:**
- Memory: < 8GB (vs 56GB+ Python)
- Speed: 10,000+ hand evaluations/sec (vs 19.4 Python)
- Training: 1,000+ MCCFR iterations/sec (vs ~10 Python)
- Clustering: < 10 minutes total (vs 2-4 hours Python)

## Stage 1: Core Hand Evaluation Engine
**Goal**: Fast, SIMD-optimized hand evaluator
**Success Criteria**: 10,000+ evaluations/second
**Tests**: Validate against all 2.6M river combinations
**Status**: Not Started

### Implementation:
```zig
// Cache-aligned structure for SIMD
const HandEvaluation = struct {
    cards: [7]u8 align(64),
    rank: u16,
    suit_mask: u16,
};

// SIMD batch evaluation
fn evaluateHandsBatch(hands: [][7]u8) [64]u16 {
    const vec_cards = @Vector(64, u8){hands...};
    // Vectorized evaluation logic
}
```

### Files to Create:
- `poker_ai/zig/src/hand_eval.zig` - Core evaluation logic
- `poker_ai/zig/src/lookup_tables.zig` - Pre-computed tables
- `poker_ai/zig/tests/test_hand_eval.zig` - Validation tests

## Stage 2: Memory-Efficient Clustering
**Goal**: Complete clustering within 8GB RAM
**Success Criteria**: Process all combinations without OOM
**Tests**: Compare cluster assignments with Python
**Status**: Partially Complete (zig_clustering exists)

### Improvements Needed:
1. Replace GPA with arena allocators
2. Add comptime configuration
3. Implement SIMD K-means
4. Fix C interop error handling

### Files to Modify:
- `poker_ai/zig_clustering/src/main.zig` - Add arena allocators
- `poker_ai/zig_clustering/src/storage.zig` - Improve error handling
- `poker_ai/zig_clustering/src/clustering.zig` - SIMD optimization

## Stage 3: Game Engine Core
**Goal**: Type-safe, zero-allocation game state management
**Success Criteria**: 1M+ state transitions/second
**Tests**: Validate all legal action sequences
**Status**: Not Started

### Implementation:
```zig
const GameState = struct {
    players: [MAX_PLAYERS]Player,
    board: [5]?Card,
    pot: u32,
    betting_round: BettingRound,
    
    // Stack-allocated, no heap usage
    fn transition(self: GameState, action: Action) GameState {
        var new_state = self;
        // Apply action logic
        return new_state;
    }
};
```

### Files to Create:
- `poker_ai/zig/src/game_state.zig` - State management
- `poker_ai/zig/src/actions.zig` - Action validation
- `poker_ai/zig/src/pot_management.zig` - Pot calculations
- `poker_ai/zig/tests/test_game_logic.zig` - Game rule tests

## Stage 4: MCCFR Training System
**Goal**: Parallel, cache-efficient CFR implementation
**Success Criteria**: 1,000+ iterations/second
**Tests**: Convergence to Nash equilibrium on Kuhn poker
**Status**: Not Started

### Implementation:
```zig
// Replace Python dict with fixed arrays
const StrategyTable = struct {
    regrets: HashMap(u64, [MAX_ACTIONS]f32),
    strategy: HashMap(u64, [MAX_ACTIONS]f32),
    
    fn updateRegrets(self: *Self, info_set: u64, values: [MAX_ACTIONS]f32) void {
        // SIMD-optimized regret updates
    }
};

// Parallel CFR workers
const CFRWorker = struct {
    thread_id: u32,
    local_regrets: StrategyTable,
    
    fn runCFR(self: *Self, iterations: u32) void {
        // Independent game tree traversals
    }
};
```

### Files to Create:
- `poker_ai/zig/src/cfr.zig` - Core CFR algorithm
- `poker_ai/zig/src/strategy_table.zig` - Regret/strategy storage
- `poker_ai/zig/src/monte_carlo.zig` - MC sampling
- `poker_ai/zig/src/parallel_cfr.zig` - Multi-threaded training
- `poker_ai/zig/tests/test_cfr_convergence.zig` - Validation

## Stage 5: C API & Python Interop
**Goal**: Seamless integration with existing Python code
**Success Criteria**: Drop-in replacement for Python modules
**Tests**: Round-trip data serialization
**Status**: Not Started

### Implementation:
```zig
// Export C-compatible interface
export fn poker_ai_create_agent(
    river_clusters: c_int,
    turn_clusters: c_int,
    flop_clusters: c_int,
) ?*opaque {
    // Create agent instance
}

export fn poker_ai_get_action(
    agent: ?*opaque,
    state: *const GameStateC,
) c_int {
    // Return best action
}
```

### Files to Create:
- `poker_ai/zig/src/c_api.zig` - C exports
- `poker_ai/python/zig_bridge.py` - Python wrapper
- `poker_ai/zig/tests/test_ffi.zig` - FFI tests

## Stage 6: Build System & Packaging
**Goal**: Cross-platform build with optimizations
**Success Criteria**: Single command build for all platforms
**Tests**: CI/CD integration
**Status**: Not Started

### build.zig Configuration:
```zig
pub fn build(b: *std.Build) void {
    // Main library
    const lib = b.addStaticLibrary(.{
        .name = "poker_ai",
        .root_source_file = b.path("src/lib.zig"),
        .optimize = .ReleaseFast,
    });
    
    // Python bindings
    const py_lib = b.addSharedLibrary(.{
        .name = "poker_ai_py",
        .root_source_file = b.path("src/c_api.zig"),
    });
    
    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("bench/main.zig"),
    });
}
```

## Migration Schedule

### Week 1-2: Foundation
- [x] Analyze Python codebase
- [x] Review existing Zig code
- [x] Design architecture
- [ ] Set up Zig project structure
- [ ] Port hand evaluation

### Week 3-4: Memory Crisis
- [ ] Fix clustering memory issues
- [ ] Implement streaming K-means
- [ ] Add checkpoint/resume

### Week 5-6: Game Logic
- [ ] Port game state management
- [ ] Implement action validation
- [ ] Add pot calculations

### Week 7-8: AI Training
- [ ] Port MCCFR algorithm
- [ ] Add parallel training
- [ ] Implement strategy compression

### Week 9-10: Integration
- [ ] Create C API
- [ ] Build Python bindings
- [ ] Migration testing

### Week 11-12: Optimization
- [ ] Performance profiling
- [ ] SIMD optimization
- [ ] Memory optimization

## Validation Milestones

1. **Hand Evaluator**: Match Python output for all 2.6M combinations
2. **Clustering**: < 8GB memory, < 10 minute runtime
3. **Game Engine**: 1M+ state transitions/second
4. **MCCFR**: Converge to Nash on Kuhn poker
5. **Integration**: Python test suite passes with Zig backend

## Risk Mitigation

### High Risk Issues:
1. **Floating-point differences**: Use deterministic rounding
2. **Memory leaks**: Arena allocators + leak detection
3. **Race conditions**: Lock-free data structures

### Fallback Strategy:
- Maintain Python-Zig hybrid during migration
- Gradual component replacement
- Extensive A/B testing

## Performance Benchmarks

```bash
# Run after each stage
zig build bench

# Expected results:
# Hand eval: 10,000+ hands/sec
# Clustering: < 8GB RAM, < 10 min
# Game state: 1M+ transitions/sec  
# MCCFR: 1,000+ iterations/sec
```

## Success Metrics

| Metric | Python | Zig Target | Actual |
|--------|--------|------------|--------|
| Memory (peak) | 56GB+ | < 8GB | TBD |
| Hand eval/sec | 19.4 | 10,000+ | TBD |
| MCCFR iter/sec | ~10 | 1,000+ | TBD |
| Clustering time | 2-4h | < 10min | TBD |
| API latency | 100ms | < 1ms | TBD |

## Next Steps

1. Create Zig project structure
2. Port hand evaluation system
3. Run first benchmarks
4. Begin incremental migration

---

*This plan is a living document. Update status and metrics as implementation progresses.*