# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a poker AI implementation using Monte Carlo Counterfactual Regret Minimization (MCCFR) to train agents that play Short Deck Poker (20-card deck with ranks 10-A). The system supports 2-6 players with a focus on multi-player (Pluribus-style) poker AI.

## Development Commands

### Installation
```bash
# Install from source for development
pip install -e .

# Install dependencies
pip install -r requirements.txt
```

### Testing
```bash
# Run all tests
pytest

# Run specific test file
pytest test/unit/test_specific.py

# Run with coverage
pytest --cov=poker_ai
```

### CLI Commands
```bash
# Generate card information lookup tables (required before training)
poker_ai cluster

# Train a new agent
poker_ai train start

# Resume training
poker_ai train resume --strategy_path path/to/strategy.gz

# Play against trained agent
poker_ai play --agent offline --strategy_path path/to/strategy.gz

# Visualize bot strategy
poker_ai viz
```

## Architecture

### Core Modules

**poker_ai/games/short_deck/**
- `state.py`: Core game state implementation with MCCFR traversal support
- `player.py`: Player representation with chip/action management
- Implements Short Deck Poker rules (20-card deck, ranks 10-A only)

**poker_ai/ai/**
- `ai.py`: MCCFR algorithm implementation
- `runner.py`: Training orchestration (default 3 players)
- `agent.py`: Strategy loading and action selection
- `multiprocess/`: Distributed training support
- `singleprocess/`: Single-threaded training

**poker_ai/clustering/**
- `card_info_lut_builder.py`: Creates lookup tables for information set abstraction
- `runner.py`: CLI interface for clustering
- Reduces 56+ billion card combinations to tractable clusters

**poker_ai/poker/**
- `table.py`: Table management (min 2 players required)
- `engine.py`: Game flow controller
- `pot.py`: Pot and side-pot logic
- `evaluation/`: Fast hand evaluation (ported from deuces)

**poker_ai/terminal/**
- `runner.py`: Terminal-based gameplay interface
- `render.py`: ASCII visualization of game state

## Key Implementation Details

### Player Limits
- Minimum: 2 players (enforced in `poker_ai/poker/table.py:28`)
- Maximum tested: 6 players
- Default: 3 players for training

### Information Set Clustering
Before training, you MUST run clustering to generate `card_info_lut.joblib`:
```bash
poker_ai cluster
```
This creates lookup tables that group strategically similar card combinations.

### State Traversal
The `ShortDeckPokerState` class supports depth-first traversal for MCCFR:
```python
state = ShortDeckPokerState(players=players)
for action in state.legal_actions:
    new_state = state.apply_action(action)
```

### Training Output
Training creates a directory with:
- `offline_strategy_*.gz`: Compressed strategy files
- `config.yaml`: Training configuration
- Strategy files are saved periodically during training

## Important Constraints

1. **20-card deck only**: Currently hardcoded to ranks 10, J, Q, K, A
2. **Clustering required**: Must run `poker_ai cluster` before training
3. **Memory intensive**: MCCFR requires significant RAM for strategy storage
4. **Python 3.7+**: Minimum Python version requirement

## Testing Patterns

Tests are organized in:
- `test/unit/`: Unit tests for individual components
- `test/functional/`: Integration tests for game scenarios

Key test files:
- `test/unit/test_state.py`: Game state logic
- `test/functional/test_engine.py`: Full game scenarios
- `test/unit/test_pot.py`: Pot distribution logic

## Common Workflows

### Training a New Agent
```bash
# 1. Generate lookup tables (one-time setup)
poker_ai cluster

# 2. Start training (creates timestamped directory)
poker_ai train start --iterations 100000

# 3. Resume if interrupted
poker_ai train resume --strategy_path ./path/to/strategy.gz
```

### Playing Against Agent
```bash
# Load specific strategy
poker_ai play --agent offline \
  --pickle_dir ./research/blueprint_algo \
  --strategy_path ./path/to/offline_strategy.gz
```

### Debugging Game State
The codebase includes visualization tools:
- Terminal UI for interactive play
- Web-based visualization server (in development)
- Strategy visualization for specific game situations