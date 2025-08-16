# Poker AI Training Guide

## Quick Start

### Fastest Way to Train
```bash
# Quick test (10K iterations, ~5-10 minutes)
./train_ai.sh quick

# Medium training (100K iterations, ~1-2 hours)
./train_ai.sh medium

# Long training (1M iterations, ~10-20 hours)
./train_ai.sh long

# Ultra long (10M iterations, ~4-7 days)
./train_ai.sh ultra

# Continuous training (runs forever)
./train_ai.sh continuous
```

### Monitor Training Progress
In a separate terminal:
```bash
# Live monitoring
python monitor_training.py

# Show summary of all runs
python monitor_training.py --summary
```

## Training Scripts

### 1. `train_ai.sh` - Easy Training Interface
The simplest way to train. Automatically handles:
- LUT generation if needed
- Training configuration
- Progress estimation
- Resume capability

**Training Modes:**
- `quick`: 10K iterations (~5-10 min) - Testing
- `medium`: 100K iterations (~1-2 hours) - Basic strategy
- `long`: 1M iterations (~10-20 hours) - Competitive
- `ultra`: 10M iterations (~4-7 days) - Professional
- `continuous`: Runs indefinitely - Maximum strength
- `resume`: Continue from last checkpoint

### 2. `train_long_ai.py` - Advanced Training Control
Python script with full control over training:

```bash
# Standard long training
python train_long_ai.py --iterations 1000000

# Resume from checkpoint
python train_long_ai.py --resume

# Continuous loop training
python train_long_ai.py --loop --loop_iterations 100000

# Custom configuration
python train_long_ai.py \
    --iterations 500000 \
    --players 4 \
    --save_interval 25000 \
    --processes 8
```

**Features:**
- Automatic LUT generation
- Resume from interruption
- Continuous training loops
- Custom save intervals
- Multi-process support

### 3. `monitor_training.py` - Progress Monitoring
Track your training in real-time:

```bash
# Live monitoring (updates every 10s)
python monitor_training.py

# Summary of all training runs
python monitor_training.py --summary
```

**Shows:**
- Current training status
- Estimated iterations completed
- Training speed (iterations/hour)
- File sizes and counts
- Multiple training run comparison

## Training Recommendations

### For Testing Your Setup
```bash
./train_ai.sh quick
```
- 10,000 iterations
- Takes 5-10 minutes
- Good for verifying everything works

### For Playing Against
```bash
./train_ai.sh medium
```
- 100,000 iterations
- Takes 1-2 hours
- Creates a playable but basic AI

### For Competitive Play
```bash
./train_ai.sh long
```
- 1,000,000 iterations
- Takes 10-20 hours (run overnight)
- Creates a strong competitive AI

### For Maximum Strength
```bash
# Start continuous training
./train_ai.sh continuous

# In another terminal, monitor progress
python monitor_training.py

# Stop with Ctrl+C when satisfied
# Resume later with:
./train_ai.sh resume
```

## Important Notes

### System Requirements
- **RAM**: 8GB minimum, 16GB+ recommended
- **Storage**: 1-10GB depending on training length
- **CPU**: Multi-core recommended (uses parallel processing)
- **Time**: Hours to days depending on iterations

### LUT Generation
- First-time setup creates `card_info_lut.joblib` (~74MB)
- Takes 15-30 minutes (one-time only)
- Automatically handled by training scripts

### Resuming Training
Training can be interrupted and resumed:
```bash
# If training is interrupted (Ctrl+C, power loss, etc.)
./train_ai.sh resume

# Or specify iterations to add
python train_long_ai.py --resume --iterations 500000
```

### Strategy Files
- Saved as `offline_strategy_XXXXXX.gz`
- Compressed format (smaller file size)
- Each save point can be used for play/testing
- Larger files = more training = stronger AI

## Testing Your Trained AI

### Against Slumbot
```bash
# Find your latest strategy file
ls -t **/offline_strategy*.gz | head -1

# Test against Slumbot
uv run test_slumbot.py --strategy_path path/to/strategy.gz
```

### Interactive Play
```bash
# Play against your AI
uv run poker_ai play --agent offline --strategy_path path/to/strategy.gz
```

## Troubleshooting

### "No module named 'poker_ai'"
```bash
# Reinstall in development mode
pip install -e .
```

### "LUT file not found"
The scripts automatically generate LUTs, but if needed:
```bash
uv run poker_ai cluster
```

### Training Too Slow
- Close other applications
- Use fewer players: `--players 2`
- Increase save interval: `--save_interval 50000`
- Check CPU usage with `top` or Activity Monitor

### Out of Memory
- Reduce number of parallel processes
- Use fewer players
- Increase save interval to reduce checkpoints

## Advanced Configuration

### Custom Training Parameters
Edit values in `train_long_ai.py`:
- `iterations`: Total training iterations
- `players`: Number of players (2-6)
- `save_interval`: Checkpoint frequency
- `processes`: Parallel processes (None=auto)

### Distributed Training
For very long training across multiple machines, see the multiprocess module documentation.

## Performance Expectations

| Training Level | Iterations | Time | Strength |
|---------------|-----------|------|----------|
| Test | 10K | 5-10 min | Very weak |
| Basic | 100K | 1-2 hours | Beginner |
| Good | 1M | 10-20 hours | Intermediate |
| Strong | 10M | 4-7 days | Advanced |
| Professional | 100M+ | Weeks | Expert |

Note: Actual times depend on your hardware.