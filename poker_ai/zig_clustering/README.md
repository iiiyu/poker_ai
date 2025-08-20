# Zig Poker Clustering System

A high-performance, memory-efficient implementation of Texas Hold'em hand abstraction using K-means clustering, written in Zig. This system replaces the memory-intensive Python implementation that was running out of RAM when processing millions of poker hand combinations.

## Overview

This implementation creates Lookup Tables (LUTs) that map poker hand combinations to cluster IDs, enabling efficient hand abstraction for poker AI systems. It processes hands through multiple stages (River → Turn → Flop), using Expected Hand Strength (EHS) calculations and K-means clustering.

## Key Features

- **Memory-Efficient**: Streaming architecture with SQLite backend for processing millions of combinations
- **Configurable Coverage**: Multiple modes from test (1k) to heavy (1M) combinations
- **Python-Compatible**: Maintains same LUT structure as Python implementation
- **Proper Poker Engine**: Complete Texas Hold'em implementation with correct hand evaluation
- **Cross-Language Support**: SQLite database enables sharing between Python and Zig

## What Was Built

### 1. Core Components

- **Card System** (`eval_card.zig`)
  - EvaluationCard representation (32-bit integers)
  - Python-compatible card ordering (suit-first)
  - Card generation and manipulation

- **Game Engine** (`game_engine.zig`)
  - Complete Texas Hold'em implementation
  - Deck, Player, Table, and Pot management
  - Game state tracking through streets

- **Hand Evaluator** (`evaluator.zig`)
  - Proper poker hand ranking (Royal Flush → High Card)
  - 7-card hand evaluation (best 5 from 7)
  - Lower rank = better hand (matching Python)

- **Equity Calculator** (`equity_calculator.zig`)
  - Expected Hand Strength (EHS) calculation
  - Monte Carlo simulation for win probability
  - Distribution calculation for next street clusters

- **LUT Builder** (`lut_builder.zig`)
  - River LUT: Maps 7 cards → EHS → cluster ID
  - Turn LUT: Maps 6 cards → distribution over river clusters → cluster ID
  - Flop LUT: Maps 5 cards → distribution over turn clusters → cluster ID
  - K-means clustering implementation

- **Storage System** (`storage.zig`)
  - SQLite integration for persistence
  - Streaming data processing
  - Checkpoint support for resumable processing

### 2. Coverage Modes

| Mode | River | Turn | Flop | Memory | Time |
|------|-------|------|------|--------|------|
| Emergency | 1k | 1k | 1k | ~20 MB | ~1 min |
| Light | 10k | 10k | 10k | ~200 MB | ~10 min |
| Medium | 100k | 50k | 50k | ~2 GB | ~1 hour |
| Heavy | 1M | 500k | 500k | ~20 GB | ~10 hours |

### 3. Key Improvements Over Python

- **Memory Usage**: Reduced from 32GB+ to configurable 20MB-20GB
- **No OOM Crashes**: Streaming architecture prevents memory exhaustion
- **Faster Processing**: Compiled Zig outperforms interpreted Python
- **Better Coverage Control**: Configurable limits for each stage

## Installation

### Prerequisites

```bash
# Install Zig (0.14.0 or later)
brew install zig

# Install SQLite development libraries
brew install sqlite3
```

### Build

```bash
cd poker_ai/zig_clustering
zig build-exe src/main.zig -lsqlite3
```

## Usage

### Basic Commands

```bash
# Run test suite
./main test

# Generate LUTs with different coverage levels
./main emergency  # Minimal memory (1k combos)
./main light      # Light coverage (10k combos)
./main medium     # Medium coverage (50-100k combos)
./main heavy      # Heavy coverage (500k-1M combos)

# Show help
./main --help
```

### Output

The system generates a SQLite database (`clustering_lut.db`) containing:
- `river_data` - River hand evaluations and clusters
- `turn_data` - Turn distributions and clusters
- `flop_data` - Flop distributions and clusters
- `checkpoints` - Resume points for long runs

## Architecture

```
Input: 52 cards
  ↓
Generate Combinations
  ├── River: C(52,2) × C(50,5) combinations
  ├── Turn: C(52,2) × C(50,4) combinations
  └── Flop: C(52,2) × C(50,3) combinations
  ↓
Calculate Features
  ├── River: EHS values
  ├── Turn: Distribution over river clusters
  └── Flop: Distribution over turn clusters
  ↓
K-Means Clustering
  ├── Mini-batch updates
  └── Configurable cluster counts
  ↓
Store in SQLite
  └── Cross-language compatible
```

## Data Structure

The LUT structure matches Python's format:

```python
LUT = {
    'river': { (card1, ..., card7): cluster_id },
    'turn': { (card1, ..., card6): cluster_id },
    'flop': { (card1, ..., card5): cluster_id },
    'preflop': { (card1, card2): cluster_id }
}
```

## Performance Considerations

1. **Memory Management**
   - Uses streaming to process combinations in batches
   - Configurable chunk size for database flushes
   - Proper cleanup of allocated memory

2. **Scaling Options**
   - Start with Light mode for development
   - Use Medium for reasonable coverage
   - Heavy mode for production systems
   - Emergency mode for minimal memory systems

3. **Database Optimization**
   - WAL mode for better concurrency
   - Indexes on cluster IDs
   - Batch transactions for performance

## Files Overview

```
src/
├── main.zig              # Entry point and configuration
├── eval_card.zig         # Card representation
├── game_engine.zig       # Texas Hold'em engine
├── evaluator.zig         # Hand evaluation
├── equity_calculator.zig # EHS calculation
├── lut_builder.zig       # LUT generation and K-means
├── storage.zig           # SQLite persistence
└── strategic_sampler.zig # Strategic hand sampling

docs/
├── ARCHITECTURE.md       # System design
└── SCALING.md           # Coverage scaling guide
```

## Integration with Python

The SQLite database can be read directly from Python:

```python
import sqlite3
import pickle

conn = sqlite3.connect('clustering_lut.db')
cursor = conn.cursor()

# Read river clusters
cursor.execute("SELECT combo_id, hand_cards, board_cards, cluster_id FROM river_data")
river_data = cursor.fetchall()

# Process as needed...
```

## Future Enhancements

- [ ] Isomorphic reduction (reduce symmetric hands)
- [ ] Parallel processing for multi-core systems
- [ ] GPU acceleration for EHS calculations
- [ ] Progressive sampling strategies
- [ ] Real-time LUT updates

## License

Part of the poker_ai project. See main project license.

## Troubleshooting

### Out of Memory
- Use emergency mode or reduce coverage limits
- Increase chunk_size for more frequent flushes
- Run on a machine with more RAM

### Slow Processing
- Reduce n_simulations parameters
- Use lighter coverage mode
- Consider sampling strategies

### Database Errors
- Ensure write permissions in directory
- Check SQLite is properly installed
- Delete corrupted database and regenerate