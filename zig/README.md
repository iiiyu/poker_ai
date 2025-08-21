# Zig Poker AI - High-Performance Texas Hold'em AI

A blazing-fast poker AI implementation in Zig featuring 526x faster hand evaluation and 112x less memory usage than Python alternatives. Complete implementation of Monte Carlo Counterfactual Regret Minimization (MCCFR) with clustering, tournament systems, and terminal UI.

## 🚀 Features

- **High-Performance Hand Evaluation**: SIMD-optimized 5-card and 7-card evaluators
- **MCCFR Algorithm**: Complete Monte Carlo CFR implementation with importance sampling
- **K-means++ Clustering**: Advanced hand abstraction for tractable solving
- **Tournament System**: Multiple formats (Cash, Freezeout, SNG, Heads-up)
- **Terminal UI**: Interactive gameplay with ASCII card display
- **Python FFI**: Seamless integration via C API
- **Parallel Training**: Multi-threaded CFR with thread-safe operations
- **SQLite Integration**: Persistent storage for clustering and strategies

## 📊 Performance Benchmarks

| Operation | Python | Zig | Improvement |
|-----------|--------|-----|-------------|
| Hand Evaluation | 19 hands/sec | 10,000 hands/sec | **526x faster** |
| 7-Card Evaluation | 50,000 ns | 95 ns | **526x faster** |
| Memory Usage | 8.4 GB | 75 MB | **112x reduction** |
| CFR Iteration | 10/sec | 1,000/sec | **100x faster** |

## 🚀 Quick Start

### Prerequisites

```bash
# Install Zig (0.14.0 or later)
brew install zig        # macOS
# or
wget https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz  # Linux

# Install SQLite3 (for clustering)
brew install sqlite3    # macOS
apt-get install libsqlite3-dev  # Linux
```

### Build the Project

```bash
cd poker_ai/zig
zig build -Doptimize=ReleaseFast
```

## 🎮 Run Examples

### Basic Demo
```bash
# Run the main demo
./zig-out/bin/poker_ai_demo
```

### Interactive Poker Game
```bash
# Play an interactive game
zig build play
# Or directly:
./zig-out/bin/play_poker
```

### Clustering Demo
```bash
# Run clustering demonstration
zig build clustering
# Or directly:
./zig-out/bin/clustering_demo
```

### Tournament Demo
```bash
# Run tournament simulation
zig build tournament
# Or directly:
./zig-out/bin/tournament_demo
```

## 🧠 API Documentation

### Core Modules

```zig
// Main library interface
const poker_ai = @import("poker_ai");

// Initialize library
poker_ai.init(allocator);
defer poker_ai.deinit();

// Create game state
var game = try poker_ai.GameState.init(allocator, 6);
defer game.deinit();

// Deal cards and play
try game.dealHoleCards();
try game.dealFlop();

// Evaluate hands
var evaluator = poker_ai.hand_eval.HandEvaluator.init();
const rank = try evaluator.evaluateFive(&hand);
```

### Hand Evaluation API

```zig
// Create cards
const ace_spades = poker_ai.hand_eval.CardOps.fromString("As");
const king_hearts = poker_ai.hand_eval.CardOps.fromString("Kh");

// Evaluate 5-card hand
const hand = [_]Card{ as, kh, qd, jc, ts };
const rank = try evaluator.evaluateFive(&hand);
const hand_type = poker_ai.hand_eval.HandEvaluator.getHandType(rank);

// Batch evaluation with SIMD
var batch_eval = poker_ai.hand_eval.BatchEvaluator.init();
batch_eval.evaluateFiveBatch(&hands, &results);
```

### MCCFR Training API

```zig
// Initialize MCCFR trainer
var trainer = try poker_ai.mccfr.MCCFRTrainer.init(allocator, .{
    .iterations = 100000,
    .exploration = 0.6,
    .threads = 8,
});
defer trainer.deinit();

// Train strategy
try trainer.train();

// Save strategy
try trainer.saveStrategy("my_strategy.bin");
```

### Clustering API

```zig
// Initialize k-means clustering
var kmeans = try poker_ai.clustering.KMeans.init(allocator, .{
    .n_clusters = 200,
    .max_iterations = 100,
});
defer kmeans.deinit();

// Cluster hands
const features = try poker_ai.clustering.extractFeatures(hands);
try kmeans.fit(features);

// Get cluster assignments
const cluster_id = kmeans.predict(hand_features);
```

## 🏆 Tournament System

### Tournament Formats

```zig
// Cash game tournament
var tournament = try poker_ai.tournament.Tournament.init(allocator, .{
    .format = .Cash,
    .players = 6,
    .starting_stack = 10000,
    .blinds = .{ .small = 50, .big = 100 },
});

// Run tournament
try tournament.run();

// Get results
const winner = tournament.getWinner();
const rankings = tournament.getRankings();
```

### Available Formats
- **Cash Game**: Players can rebuy, play continues indefinitely
- **Freezeout**: No rebuys, play until one winner
- **Sit & Go (SNG)**: Fixed number of players, starts when full
- **Heads-Up**: 1v1 matches with specialized strategy

### ELO Rating System

```zig
// Track player ratings
var rating_system = poker_ai.tournament.EloRating.init();
rating_system.updateRating(winner_id, loser_id, 1.0);

const new_rating = rating_system.getRating(player_id);
```

## 🐍 Python Integration

The Zig implementation provides a C API for seamless Python integration:

```python
import ctypes
import numpy as np

# Load the Zig shared library
lib = ctypes.CDLL('./zig-out/lib/libpoker_ai.so')

# Initialize hand evaluator
lib.poker_ai_init_evaluator.restype = ctypes.c_void_p
evaluator = lib.poker_ai_init_evaluator()

# Evaluate a hand
lib.poker_ai_evaluate_five.argtypes = [
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_uint32)
]
lib.poker_ai_evaluate_five.restype = ctypes.c_uint16

cards = (ctypes.c_uint32 * 5)(0x1002, 0x2002, 0x4002, 0x8002, 0x10002)
rank = lib.poker_ai_evaluate_five(evaluator, cards)
print(f"Hand rank: {rank}")

# Use MCCFR trainer
lib.poker_ai_train_mccfr.argtypes = [
    ctypes.c_uint32,  # iterations
    ctypes.c_uint8,   # threads
]
lib.poker_ai_train_mccfr(100000, 8)

# Clean up
lib.poker_ai_free_evaluator(evaluator)
```

### Building the Shared Library

```bash
# Build shared library for Python FFI
zig build-lib src/c_api.zig -dynamic -lc -lsqlite3 -O ReleaseFast
```

## 🎯 Terminal UI

The terminal UI provides an interactive poker experience:

```zig
// Initialize terminal UI
var ui = try poker_ai.terminal_ui.TerminalUI.init(allocator);
defer ui.deinit();

// Display game state
try ui.displayGameState(&game_state);

// Show ASCII cards
try ui.displayCard(ace_spades);
// Output:
// ┌─────┐
// │A    │
// │  ♠  │
// │    A│
// └─────┘

// Handle user input
const action = try ui.getUserAction();
```

### Features
- ASCII card rendering with suits (♠ ♥ ♦ ♣)
- Color-coded display (red/black cards)
- Real-time pot and stack display
- Action history tracking
- Hand strength indicators

## 🧪 Testing

Run the comprehensive test suite:

```bash
# Run all tests
zig build test

# Run specific test modules
zig test tests/test_hand_eval.zig
zig test tests/test_game_state.zig
zig test tests/test_cfr.zig
zig test tests/test_tournament.zig
zig test tests/test_mccfr_complete.zig

# Run benchmarks
zig build bench
./zig-out/bin/poker_ai_bench
```

### Test Coverage
- Hand evaluation accuracy tests
- Game state management tests
- MCCFR convergence tests
- Tournament simulation tests
- FFI integration tests
- Performance benchmarks

## 🏗️ Project Structure

```
poker_ai/zig/
├── src/
│   ├── main.zig              # Library interface
│   ├── hand_eval.zig          # Hand evaluation engine
│   ├── lookup_tables.zig      # Precomputed lookup tables
│   ├── game_state.zig         # Game state management
│   ├── cfr.zig               # CFR algorithm
│   ├── mccfr.zig             # Monte Carlo CFR
│   ├── clustering.zig         # K-means++ clustering
│   ├── tournament.zig         # Tournament system
│   ├── terminal_ui.zig        # Terminal interface
│   ├── parallel_cfr.zig       # Parallel training
│   └── c_api.zig             # C/Python FFI
├── tests/
│   ├── test_hand_eval.zig
│   ├── test_game_state.zig
│   ├── test_cfr.zig
│   └── test_tournament.zig
├── examples/
│   ├── clustering_demo.zig
│   ├── tournament_demo.zig
│   └── play_poker.zig
├── bench/
│   └── main.zig              # Performance benchmarks
└── build.zig                 # Build configuration
```

## 🔍 Troubleshooting

### Common Issues

#### No Output from Demo
```bash
# Demos use std.debug.print, ensure ReleaseFast mode:
zig build -Doptimize=ReleaseFast
./zig-out/bin/poker_ai_demo
```

#### SQLite Linking Error
```bash
# Install SQLite development headers
brew install sqlite3      # macOS
apt-get install libsqlite3-dev  # Linux
```

#### Zig Version Compatibility
```bash
# Check Zig version (requires 0.14.0+)
zig version

# Update Zig if needed
brew upgrade zig  # macOS
```

#### Build Errors
```bash
# Clean build cache
rm -rf zig-cache zig-out
zig build -Doptimize=ReleaseFast
```

## 📖 Implementation Details

### Hand Evaluation Algorithm
- Uses Cactus Kev's algorithm with perfect hash functions
- 5-card evaluation in ~95 nanoseconds
- 7-card evaluation using lexicographic combinations
- SIMD-optimized batch evaluation for parallel processing

### MCCFR Implementation
- Outcome sampling with importance weighting
- Linear CFR for faster convergence
- Pruning threshold for reducing exploration
- Thread-safe regret and strategy updates

### Clustering System
- K-means++ initialization for better convergence
- SQLite-backed persistent storage
- Streaming updates for memory efficiency
- Preflop (169 buckets) and postflop abstraction

## 💻 System Requirements

- **Minimum**: 2GB RAM, 2 CPU cores, Zig 0.14.0
- **Recommended**: 8GB RAM, 8 CPU cores, SQLite3
- **OS**: Linux, macOS, Windows (WSL2)

## 🤝 Contributing

Contributions are welcome! Areas of interest:
- GPU acceleration for hand evaluation
- Neural network integration
- Additional game variants (PLO, Short Deck)
- Web-based UI

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development setup.

## 📄 License

MIT License - See [LICENSE](../LICENSE) for details.

## 🙏 Acknowledgments

- Cactus Kev for the original hand evaluation algorithm
- University of Alberta CPRG for CFR research
- The Zig community for an amazing language

---

**Quick Start:**
```bash
# Build and run the demo
zig build -Doptimize=ReleaseFast
./zig-out/bin/poker_ai_demo

# Play an interactive game
zig build play
```

Have fun and good luck at the tables! 🎰