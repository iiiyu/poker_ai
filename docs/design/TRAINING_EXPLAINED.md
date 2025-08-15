# Poker AI Training and Storage Explained

## Overview

This poker AI uses **Monte Carlo Counterfactual Regret Minimization (MCCFR)** to train agents that learn optimal poker strategies through self-play. The training process iteratively improves the agent's strategy by minimizing regret (the difference between what it should have done vs. what it did).

## Training Process

### 1. Prerequisites
Before training, you must generate card information lookup tables:
```bash
uv run poker_ai cluster
```
This creates `card_info_lut.joblib` which clusters similar card combinations to make the problem tractable.

### 2. Starting Training
```bash
uv run poker_ai train start --n_iterations 10000
```

Key parameters:
- `--n_iterations`: Total training iterations (default: 10000)
- `--n_players`: Number of players (default: 3)
- `--dump_iteration`: Save strategy every N iterations (default: 20)
- `--single_process/--multi_process`: Use single or multiple processes

### 3. What Happens During Training

The training creates a timestamped directory like `results_2025_01_14_10_30_45/` containing:

```
results_2025_01_14_10_30_45/
├── config.yaml              # Training configuration
├── agent.joblib            # Complete agent state
├── offline_strategy_*.gz   # Compressed strategy snapshots
└── server.gz               # Server state (for resuming)
```

## What Gets Saved

### 1. **Agent State** (`agent.joblib`)
Contains the complete agent with:
```python
{
    "regret": {
        # Information set -> action -> regret value
        "Kh Kd | ": {"fold": -100, "call": 200, "raise": 50},
        ...
    },
    "strategy": {
        # Information set -> action -> probability
        "Kh Kd | ": {"fold": 0.1, "call": 0.6, "raise": 0.3},
        ...
    },
    "pre_flop_strategy": {
        # More detailed preflop strategies
        ...
    },
    "timestep": 10000  # Current iteration
}
```

### 2. **Strategy Snapshots** (`offline_strategy_*.gz`)
Compressed files saved periodically containing:
- **Strategy**: The agent's current playing strategy
- **Regret**: Accumulated regret values
- **Timestep**: Iteration number when saved

Example: `offline_strategy_1000.gz`, `offline_strategy_2000.gz`, etc.

### 3. **Information Sets**
An information set represents what a player knows:
- Their cards
- Public cards  
- Betting history

Example: `"Kh Kd | "` means holding King of Hearts and King of Diamonds with no betting yet.

## Understanding the Strategy

The strategy maps information sets to action probabilities:

```python
# Example strategy entry
"Ah Ad | ": {           # Holding pocket aces, no bets yet
    "fold": 0.0,        # Never fold
    "call": 0.2,        # Call 20% of the time  
    "raise": 0.8        # Raise 80% of the time
}
```

## Using Trained Models

### 1. Load and Play Against AI
```bash
uv run poker_ai play \
  --agent offline \
  --strategy_path ./results_2025_01_14/offline_strategy_10000.gz
```

### 2. Load in Python Code
```python
import joblib

# Load complete agent
agent = joblib.load("results_2025_01_14/agent.joblib")

# Load specific strategy snapshot
strategy_dict = joblib.load("offline_strategy_10000.gz")
strategy = strategy_dict['strategy']
regret = strategy_dict['regret']

# Get strategy for specific situation
info_set = "Kh Kd | "  # Pocket kings, no betting
action_probs = strategy.get(info_set, {"fold": 1/3, "call": 1/3, "raise": 1/3})
```

### 3. Resume Training
```bash
uv run poker_ai train resume \
  --server_config_path ./results_2025_01_14/server.gz
```

## Key Concepts

### Regret
- Measures how much the agent regrets not taking an action
- Positive regret: Should have taken this action more
- Negative regret: Should have taken this action less

### Strategy Convergence
- Early iterations: High variance, exploring different strategies
- Later iterations: Converges toward Nash equilibrium (unexploitable strategy)

### Information Set Abstraction
- Full poker has billions of possible states
- Clustering groups similar situations (e.g., AA vs KK treated similarly to KK vs QQ)
- Makes the problem computationally tractable

## Training Tips

1. **Start Small**: Begin with fewer iterations (1000-5000) to test
2. **Monitor Progress**: Check strategy files to see if sensible patterns emerge
3. **Memory Usage**: Multi-process training uses significant RAM
4. **Save Frequency**: Adjust `--dump_iteration` based on training length

## Example Training Session

```bash
# 1. Generate lookup tables (one-time)
uv run poker_ai cluster

# 2. Train for 10,000 iterations
uv run poker_ai train start \
  --n_iterations 10000 \
  --n_players 3 \
  --dump_iteration 1000 \
  --nickname "my_first_agent"

# 3. Directory created: results_my_first_agent_2025_01_14_10_30_45/

# 4. Play against the trained agent
uv run poker_ai play \
  --agent offline \
  --strategy_path ./results_my_first_agent_2025_01_14_10_30_45/offline_strategy_10000.gz
```

## File Sizes

Typical file sizes for a trained agent:
- `agent.joblib`: 10-100 MB (depends on iterations)
- `offline_strategy_*.gz`: 5-50 MB each (compressed)
- `card_info_lut.joblib`: 50-200 MB (card clustering data)

## Interpreting Results

Good signs your agent is learning:
1. **Preflop**: Strong hands (AA, KK) have high raise probabilities
2. **Bluffing**: Some weak hands occasionally raise
3. **Folding**: Weak hands fold to aggression
4. **Mixed Strategy**: Not purely deterministic (some randomization)

The agent learns through self-play, discovering strategies that work against itself, gradually approaching game-theoretic optimal play.