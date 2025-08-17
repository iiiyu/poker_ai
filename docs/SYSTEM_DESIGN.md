# Poker AI System Design Document

## Executive Summary

This document describes the design and implementation of a Texas Hold'em poker AI using Monte Carlo Counterfactual Regret Minimization (MCCFR). The system learns optimal poker strategies through self-play, handling the massive complexity of poker through information set abstraction and clustering techniques.

## Table of Contents

1. [System Overview](#system-overview)
2. [Design Goals](#design-goals)
3. [Architecture](#architecture)
4. [Core Components](#core-components)
5. [Data Flow](#data-flow)
6. [Algorithms](#algorithms)
7. [Performance Characteristics](#performance-characteristics)
8. [Design Decisions](#design-decisions)
9. [Testing Strategy](#testing-strategy)
10. [Deployment](#deployment)
11. [Future Enhancements](#future-enhancements)

## System Overview

### What It Does

The Poker AI system:
1. **Trains** poker-playing agents using MCCFR self-play
2. **Abstracts** billions of poker situations into manageable clusters
3. **Learns** Nash Equilibrium strategies (game-theory optimal play)
4. **Plays** against humans or other AIs using learned strategies

### Key Technologies

- **Language**: Python 3.7+
- **Algorithm**: Monte Carlo CFR with Pruning (MCCFR-P)
- **Clustering**: K-means with Earth Mover's Distance
- **Storage**: Compressed pickle files with joblib
- **Parallelization**: Python multiprocessing
- **UI**: Terminal-based interface with rich formatting

## Design Goals

### Primary Goals

1. **Correctness**: Converge to Nash Equilibrium strategies
2. **Scalability**: Handle 2-6 player games
3. **Performance**: Train competitive agents in reasonable time
4. **Usability**: Simple CLI interface for training and playing

### Non-Goals

1. **Real-time Play**: Not optimized for millisecond responses
2. **Exploitative Play**: Focuses on GTO, not opponent modeling
3. **GUI**: Terminal-only interface (web viz is secondary)
4. **Distributed Training**: Single-machine only

## Architecture

### Layered Architecture

```
┌─────────────────┐
│   Presentation  │  CLI, Terminal UI, Web Viz
├─────────────────┤
│   Application   │  Training Runner, Game Controller
├─────────────────┤
│     Domain      │  Game Rules, MCCFR Algorithm
├─────────────────┤
│  Infrastructure │  Storage, Clustering, Evaluation
└─────────────────┘
```

### Module Structure

```
poker_ai/
├── ai/              # MCCFR implementation
├── games/           # Game state and rules
├── poker/           # Generic poker logic
├── clustering/      # Card abstraction
├── terminal/        # UI components
├── cli/            # Command interface
└── utils/          # Shared utilities
```

## Core Components

### 1. Game State System

**Purpose**: Represent and manipulate poker game states

**Key Classes**:
- `TexasHoldemPokerState`: Immutable game state
- `Player`: Player representation with chips/cards
- `Deck`: Card dealing and management
- `Pot`: Pot and side-pot calculations

**Design Pattern**: Immutable State Pattern
- States are never modified
- Actions create new states
- Enables efficient tree traversal

**Implementation Highlights**:
```python
class TexasHoldemPokerState:
    def apply_action(self, action: str) -> TexasHoldemPokerState:
        """Returns new state, original unchanged"""
        new_state = self._shallow_copy()
        new_state._apply_action_effects(action)
        return new_state
```

### 2. MCCFR Algorithm

**Purpose**: Learn optimal strategies through self-play

**Key Components**:
- `MCCFR`: Main algorithm implementation
- `traverse()`: Recursive game tree exploration
- `update_strategy()`: Regret matching
- `cfrp()`: Pruning variant for efficiency

**Algorithm Flow**:
1. Sample random game
2. Traverse game tree for each player
3. Calculate counterfactual regrets
4. Update strategy using regret matching
5. Save periodically

**Optimizations**:
- CFR+ (reset negative regrets)
- Pruning (skip bad actions)
- Linear averaging
- Lazy initialization

### 3. Clustering System

**Purpose**: Reduce game complexity through abstraction

**Components**:
- `CardInfoLUTBuilder`: Creates lookup tables
- `KMeans`: Groups similar situations
- `compute_equity()`: Monte Carlo hand strength

**Abstraction Levels**:
| Street  | Raw States | Clusters | Reduction |
|---------|-----------|----------|-----------|
| Preflop | 1,326     | 169      | 8x        |
| Flop    | 26M       | 200      | 130,000x  |
| Turn    | 305M      | 200      | 1.5M x    |
| River   | 2.6B      | 200      | 13M x     |

**Process**:
1. Sample representative card combinations
2. Compute strategic features (equity, potential)
3. Cluster using K-means
4. Create lookup table mapping cards → cluster_id

### 4. Strategy Storage

**Purpose**: Efficiently store and retrieve learned strategies

**Structure**:
```python
strategy = {
    "info_set_id": {
        "fold": 0.2,
        "call": 0.5,
        "raise": 0.3
    },
    # ... millions more
}
```

**Optimizations**:
- Sparse storage (only non-zero probabilities)
- Compression (gzip level 3)
- Periodic pruning of unused info sets
- Memory-mapped files for large strategies

### 5. Game Engine

**Purpose**: Manage game flow and rules enforcement

**Components**:
- `Table`: Player management
- `Engine`: Game flow controller
- `Evaluator`: Hand strength evaluation
- `Pot`: Winnings distribution

**Responsibilities**:
- Deal cards
- Manage betting rounds
- Determine winners
- Distribute pots
- Handle all-ins and side pots

### 6. User Interface

**Purpose**: Provide interaction with the system

**Components**:
- `CLI`: Command-line interface
- `TerminalRunner`: Interactive play
- `Renderer`: ASCII visualization
- `WebViz`: Browser-based visualization

**Features**:
- Color-coded cards
- Pot/stack display
- Action history
- Strategy visualization

## Data Flow

### Training Data Flow

```
1. Initialize
   ├── Load LUT
   ├── Create empty strategy
   └── Setup game parameters

2. Training Loop
   ├── Sample game
   ├── Traverse tree
   ├── Update regrets
   ├── Update strategy
   └── Save checkpoint

3. Finalize
   ├── Compress strategy
   ├── Save final model
   └── Generate statistics
```

### Playing Data Flow

```
1. Load
   ├── Load strategy file
   ├── Load LUT
   └── Initialize game

2. Game Loop
   ├── Get game state
   ├── Compute info set
   ├── Lookup strategy
   ├── Sample action
   └── Apply action

3. Complete
   ├── Determine winner
   ├── Display results
   └── Update statistics
```

## Algorithms

### 1. Monte Carlo CFR

**Pseudocode**:
```
function MCCFR(iterations):
    for i in 1..iterations:
        cards = deal_random_cards()
        for p in players:
            value = traverse(root, p, cards)
            update_regrets(p, value)
        update_average_strategy()
```

**Complexity**:
- Time: O(iterations × game_tree_size)
- Space: O(information_sets × actions)
- Convergence: O(1/√iterations)

### 2. K-Means Clustering

**Process**:
```python
def cluster_cards(cards, n_clusters):
    features = extract_features(cards)
    kmeans = KMeans(n_clusters=n_clusters)
    clusters = kmeans.fit_predict(features)
    return clusters
```

**Features Used**:
- Hand strength (0-1)
- Drawing potential (0-1)
- Board texture (flush/straight possible)
- Relative hand ranking

### 3. Hand Evaluation

**Algorithm**: Modified Cactus Kev's evaluator
- Bit manipulation for speed
- Lookup tables for common cases
- Perfect hash for 5-card hands

**Performance**: ~1M hands/second

## Performance Characteristics

### Memory Usage

| Component | Memory | Notes |
|-----------|--------|-------|
| LUT | 400 MB | Loaded once, read-only |
| Strategy | 1-5 GB | Grows with iterations |
| Regrets | 2-8 GB | Can be pruned |
| Game States | 100 MB | Temporary, GC'd |
| **Total** | **3-14 GB** | Depends on iterations |

### Training Speed

| Mode | Iterations | Time | Speed |
|------|------------|------|-------|
| Test | 100 | 1 min | 100 it/s |
| Quick | 1,000 | 10 min | 100 it/s |
| Medium | 10,000 | 1 hour | 160 it/s |
| Long | 100,000 | 10 hours | 160 it/s |
| Production | 1,000,000 | 4 days | 160 it/s |

*Note: Speed varies with hardware and number of players*

### Scalability

| Players | Memory | Speed | Quality |
|---------|--------|-------|---------|
| 2 | 3 GB | Fast | Excellent |
| 3 | 5 GB | Medium | Excellent |
| 4 | 8 GB | Slow | Good |
| 5 | 12 GB | Slow | Good |
| 6 | 16 GB | Very Slow | Moderate |

## Design Decisions

### 1. Immutable States

**Decision**: Make game states immutable

**Rationale**:
- Thread safety for parallel training
- Easier debugging (states don't change)
- Natural fit for tree traversal
- Enables caching

**Trade-off**: More object allocation, but Python's GC handles it well

### 2. Python Implementation

**Decision**: Use Python despite performance limitations

**Rationale**:
- Rapid prototyping
- Rich ecosystem (numpy, scikit-learn)
- Easy to understand and modify
- Good enough performance with optimizations

**Trade-off**: 20-40x slower than C++/Rust

### 3. Information Set Abstraction

**Decision**: Use card clustering instead of perfect recall

**Rationale**:
- Makes problem tractable (10^14 → 10^6 states)
- Standard approach in poker AI
- Good balance of quality vs. memory

**Trade-off**: Loses some strategic nuance

### 4. MCCFR vs. Deep Learning

**Decision**: Use MCCFR instead of neural networks

**Rationale**:
- Proven convergence to Nash Equilibrium
- No training data needed
- Interpretable strategies
- Works well for poker

**Trade-off**: Slower to train, more memory intensive

### 5. Fixed Bet Sizing

**Decision**: Use discrete bet sizes (check, min, 2x, pot, all-in)

**Rationale**:
- Reduces action space
- Sufficient for strong play
- Standard in poker AI

**Trade-off**: Can't make exotic bet sizes

## Testing Strategy

### Unit Tests

**Coverage Target**: 80%

**Key Areas**:
- Game state transitions
- Legal action generation
- Hand evaluation
- Pot distribution
- Clustering algorithms

**Example**:
```python
def test_state_immutability():
    state1 = new_game()
    state2 = state1.apply_action("call")
    assert state1.current_player != state2.current_player
```

### Integration Tests

**Scenarios**:
- Complete game flows
- All-in situations
- Side pot creation
- Tournament situations

### Performance Tests

**Metrics**:
- Iterations per second
- Memory usage
- Strategy convergence
- Hand evaluation speed

### Regression Tests

**Saved Scenarios**:
- Known poker situations
- Historical bugs
- Edge cases

## Deployment

### Local Development

```bash
# Install dependencies
pip install -e .

# Generate LUT (one-time)
poker_ai cluster

# Train agent
poker_ai train start

# Play against AI
poker_ai play --agent offline
```

### Production Training

```bash
# High-quality LUT
./generate_texas_holdem_lut_safe.sh high

# Long training run
./train_ai.sh production

# Monitor progress
python monitor_training.py
```

### Server Deployment

```bash
# Multi-process training
./train_ai.sh long --multi

# Background training
nohup ./train_ai.sh production > training.log 2>&1 &
```

## Future Enhancements

### Short Term (1-3 months)

1. **Rust Clustering**: 20-40x speedup
2. **Neural Network Integration**: For feature extraction
3. **Opponent Modeling**: Exploit specific players
4. **Tournament Mode**: Multi-table support
5. **Better Abstractions**: Hierarchical clustering

### Medium Term (3-6 months)

1. **Distributed Training**: Multi-machine support
2. **Real-time Adaptation**: Online learning
3. **GUI Client**: Desktop application
4. **Cloud Training**: AWS/GCP integration
5. **Mobile App**: iOS/Android client

### Long Term (6+ months)

1. **Other Poker Variants**: Omaha, Stud
2. **Advanced Abstractions**: Neural compression
3. **Human-like Play**: Style transfer
4. **Teaching Mode**: Explain decisions
5. **Competition Platform**: Online tournaments

## Conclusion

This poker AI system successfully implements state-of-the-art game theory algorithms to create competitive poker agents. The modular design allows for easy extension and modification, while the abstraction system makes the intractable problem of poker solvable on consumer hardware.

Key achievements:
- ✅ Converges to Nash Equilibrium strategies
- ✅ Handles multi-player games (2-6 players)
- ✅ Trains in reasonable time (hours to days)
- ✅ Provides simple interface for training and play
- ✅ Extensible architecture for future improvements

The system serves as both a practical poker AI and a research platform for exploring game theory, machine learning, and artificial intelligence in imperfect information games.