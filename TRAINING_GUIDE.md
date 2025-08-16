# 🎯 Poker AI Training Guide

This guide shows you how to quickly train a poker AI agent for testing.

## 🚀 Quick Start (Fastest Option)

Train a minimal agent in **under 5 minutes**:

```bash
# Option 1: Using the shell script (recommended)
./quick_train.sh quick

# Option 2: Using Python directly
uv run python train_and_test.py

# Option 3: Using the CLI
uv run poker_ai train start --n_players 2 --n_iterations 50
```

## 📊 Training Options

### Training Sizes

| Size | Iterations | Players | Time | Quality | Use Case |
|------|------------|---------|------|---------|----------|
| **quick** | 10 | 2 | ~30 sec | Poor | Quick testing only |
| **small** | 100 | 2-4 | ~5 min | Basic | Development testing |
| **medium** | 1,000 | 2-6 | ~30 min | Decent | Gameplay testing |
| **large** | 10,000 | 2-8 | ~5 hours | Good | Actual play |
| **full** | 100,000+ | 2-8 | Days | Excellent | Competition |

### Using the Training Script

```bash
# Quick 2-player agent (fastest)
./quick_train.sh quick

# Small 4-player agent
./quick_train.sh small 4

# Medium 6-player agent
./quick_train.sh medium 6
```

## 🎮 Training Methods

### Method 1: Shell Script (Easiest)
```bash
./quick_train.sh small 2
```

### Method 2: Python Script
```python
# train_and_test.py already configured for minimal training
uv run python train_and_test.py
```

### Method 3: CLI with Custom Parameters
```bash
uv run poker_ai train start \
    --n_players 2 \
    --n_iterations 100 \
    --dump_iteration 25 \
    --save_path trained_agents/my_agent \
    --single_process
```

### Method 4: Python API
```python
from poker_ai.games.texas_holdem.state import new_game
from poker_ai.ai.ai import AI

# Create AI trainer
ai = AI(n_players=2, save_path="./my_agent")

# Train
game = new_game(n_players=2)
for i in range(100):
    ai.train_one_iteration(game, i)
    if i % 25 == 0:
        ai.save_agent(i)
```

## ⚙️ Training Parameters

### Essential Parameters
- `n_players`: Number of players (2-8, fewer = faster)
- `n_iterations`: Training iterations (more = better but slower)
- `dump_iteration`: How often to save checkpoints
- `save_path`: Where to save the trained agent

### Advanced Parameters
- `strategy_interval`: How often to update strategy (default: 2)
- `prune_threshold`: Remove rare paths (default: 200)
- `c`: Exploration constant for MCCFR (default: 1.0)
- `lcfr_threshold`: Linear CFR threshold (default: 400)
- `discount_interval`: How often to discount regrets (default: 10)
- `update_threshold`: Minimum updates before saving (default: 0)

## 🧪 Testing Your Agent

### 1. Play in Terminal
```bash
# Play against your trained agent
uv run poker_ai terminal --n_players 2
```

### 2. Run Automated Games
```bash
# Watch AI vs AI
uv run poker_ai play --n_players 2
```

### 3. Use with API
```bash
# Start API server
./start_api.sh local

# Your agent will be automatically loaded
```

### 4. Test in Python
```python
from poker_ai.games.texas_holdem.state import new_game

# Create game
game = new_game(n_players=2)

# Play some actions
while not game.is_terminal:
    legal_actions = game.legal_actions
    if legal_actions:
        action = legal_actions[0]  # or use your agent
        game = game.apply_action(action)
```

## 💡 Tips for Faster Training

1. **Use fewer players**: 2 players (heads-up) trains fastest
2. **Skip card lookup tables**: Add `--pickle_dir False`
3. **Use single process**: Add `--single_process` flag
4. **Reduce iterations**: Start with 50-100 for testing
5. **Save less frequently**: Increase `dump_iteration`

## 📈 Training Progress

Monitor training progress:

```bash
# Watch the training output
uv run poker_ai train start --n_iterations 100 --verbose

# Check saved files
ls -la trained_agents/my_agent/
```

## 🎯 Example: Train for Different Purposes

### For Quick Testing (1 minute)
```bash
uv run poker_ai train start \
    --n_players 2 \
    --n_iterations 50 \
    --single_process
```

### For Development (5 minutes)
```bash
./quick_train.sh small 2
```

### For Gameplay Testing (30 minutes)
```bash
./quick_train.sh medium 4
```

### For Serious Play (5+ hours)
```bash
uv run poker_ai train start \
    --n_players 6 \
    --n_iterations 10000 \
    --dump_iteration 1000
```

## 🔍 Verify Training

Check that training worked:

```bash
# List saved files
ls -la trained_agents/*/

# Expected files:
# - agent.joblib (optional, main agent file)
# - offline_strategy_*.gz (strategy files)
# - checkpoint_*.pkl (checkpoints)
```

## ❗ Common Issues

### Issue: Training takes too long
**Solution**: Reduce iterations, use 2 players, add `--single_process`

### Issue: Out of memory
**Solution**: Use `--pickle_dir False` to skip loading large files

### Issue: No strategy files saved
**Solution**: Make sure `dump_iteration` is less than `n_iterations`

## 🎮 Next Steps

After training your agent:

1. **Test it**: `uv run poker_ai terminal --n_players 2`
2. **Improve it**: Train with more iterations
3. **Use the API**: `./start_api.sh local`
4. **Train variants**: Try different player counts
5. **Optimize**: Tune hyperparameters for better play

## 📚 Understanding Training

The training uses **Monte Carlo Counterfactual Regret Minimization (MCCFR)**:
- Each iteration improves the strategy
- More iterations = stronger play
- Convergence typically needs 10,000+ iterations
- For testing, even 50 iterations gives a playable agent

Happy training! 🎰