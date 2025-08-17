# 🎯 Poker AI Training Guide

This guide shows you how to train a Texas Hold'em poker AI agent using MCCFR.

## 📋 Prerequisites

Before training, you MUST generate the Card Info LUT:

```bash
# Generate LUT (one-time, 2-4 hours for standard quality)
./generate_texas_holdem_lut.sh standard

# Or use test mode for quick development (30-60 min)
./generate_texas_holdem_lut.sh test
```

## 🚀 Quick Start

Once you have the LUT, train an agent:

```bash
# Test mode - verify everything works (100 iterations, ~1 minute)
./train_ai.sh test

# Quick mode - basic strategy (1K iterations, ~2-5 minutes)
./train_ai.sh quick

# Medium mode - decent strategy (100K iterations, ~3-8 hours)
./train_ai.sh medium --multi  # Use --multi for 2-3x speed
```

## 📊 Training Options

### Training Modes (Updated for Texas Hold'em)

| Mode | Iterations | Time (Single) | Time (Multi) | Quality | Use Case |
|------|------------|---------------|--------------|---------|----------|
| **test** | 100 | ~30s-1m | ~20-40s | Minimal | Verify setup |
| **quick** | 1,000 | ~2-5 min | ~1-3 min | Basic | Quick testing |
| **medium** | 100,000 | ~3-8 hours | ~2-4 hours | Good | Decent play |
| **long** | 1,000,000 | ~30-80 hours | ~15-40 hours | Strong | Competitive |
| **ultra** | 10,000,000 | ~2-4 weeks | ~1-2 weeks | Pro | Tournament |

**Note**: Actual times depend on CPU, number of players, and system load.

### Using the Enhanced Training Script

```bash
# Test training - verify everything works
./train_ai.sh test

# Quick training with multiprocessing (faster)
./train_ai.sh quick --multi

# Medium training with 2 players (faster than 3+)
./train_ai.sh medium --players 2 --multi

# Resume interrupted training
./train_ai.sh resume

# Continuous training (runs indefinitely)
./train_ai.sh continuous
```

## 📊 Monitoring Training Progress

### Real-time Monitoring
```bash
# In another terminal while training runs
python monitor_training.py
```

Shows:
- Current iteration and speed (iterations/sec)
- Estimated time remaining
- Strategy file size and location
- System resource usage

### Performance Expectations

**Single Process**:
- ~5-15 iterations/second
- Better for small tests
- Less memory usage

**Multiprocess** (--multi flag):
- ~20-50 iterations/second
- 2-3x faster than single
- Requires more RAM

## 🎮 Training Methods

### Method 1: Shell Script (Recommended)
```bash
# Best for most users
./train_ai.sh medium --multi
```

### Method 2: Python Script with Custom Settings
```bash
python train_long_ai.py \
    --iterations 100000 \
    --players 3 \
    --save_interval 5000
```

### Method 3: CLI with Full Control
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