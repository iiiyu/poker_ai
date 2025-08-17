# Clustering and LUT Generation Guide

## Overview

The Card Information Lookup Table (LUT) is essential for poker AI training. It groups similar card combinations into clusters to make the game computationally tractable. Without clustering, Texas Hold'em has over 10^14 possible card combinations, which is impossible to handle directly.

## Quick Start

### 🛡️ Use the Safe Script (Recommended)

The safe script includes resume capability, automatic retry, and resource monitoring:

```bash
# Generate with automatic resume on crash
./generate_texas_holdem_lut_safe.sh standard

# Check generation status
./generate_texas_holdem_lut_safe.sh standard status

# Resume after interruption
./generate_texas_holdem_lut_safe.sh standard resume
```

### Quick Command Reference

```bash
# Check if LUT already exists and its status
./generate_texas_holdem_lut_safe.sh standard status

# Generate for testing (fastest)
./generate_texas_holdem_lut_safe.sh test

# Generate for training (balanced)
./generate_texas_holdem_lut_safe.sh standard

# Generate for production (best quality)
./generate_texas_holdem_lut_safe.sh high

# Resume interrupted generation
./generate_texas_holdem_lut_safe.sh [mode] resume

# Check progress of existing LUT
python check_lut_progress.py

# Monitor clustering in real-time (separate terminal)
python monitor_clustering.py
```

### Generate Standard Quality LUT
```bash
./generate_texas_holdem_lut_safe.sh standard
```
- Time: 2-4 hours
- Size: ~300-400MB
- Quality: Good for competitive play
- **Auto-resumes if interrupted**

### Generate Test LUT (For Development)
```bash
./generate_texas_holdem_lut_safe.sh test
```
- Time: 30-60 minutes
- Size: ~150-200MB
- Quality: Sufficient for testing
- **Fast iteration for development**

### Generate High Quality LUT (For Production)
```bash
./generate_texas_holdem_lut_safe.sh high
```
- Time: 6-10 hours
- Size: ~500-700MB
- Quality: Professional level
- **Best for final deployment**

## Understanding the Process

### 1. What is Clustering?

Clustering groups similar poker situations together to reduce complexity:
- **River**: Groups 133M+ combinations into 200-500 clusters
- **Turn**: Groups 20M+ combinations into 200-500 clusters  
- **Flop**: Groups 2.6M+ combinations into 200-500 clusters
- **Preflop**: Groups 1,326 combinations into 169 unique hands

### 2. Why 70MB Was Wrong

Your previous 70MB file was using:
- Short deck (20 cards, ranks 10-14)
- Only 50 clusters per stage
- Minimal simulations (6)

Full Texas Hold'em requires:
- Full deck (52 cards, ranks 2-14)
- 200+ clusters per stage
- 10+ simulations for accuracy

### 3. File Size Expectations

| Mode | Clusters | Simulations | Size | Time |
|------|----------|-------------|------|------|
| Test | 50 | 5 | ~150-200MB | 30-60 min |
| Standard | 200 | 10 | ~300-400MB | 2-4 hours |
| High | 500 | 20 | ~500-700MB | 6-10 hours |

## Monitoring Progress

### Real-time Monitoring
```bash
# In another terminal while clustering runs
python monitor_clustering.py
```

Shows:
- Current stage (River/Turn/Flop)
- Progress percentage
- Estimated time remaining
- System resource usage

### Understanding the Stages

1. **River Processing** (Fast)
   - ~133M combinations
   - ~5-10 minutes
   - Progress updates frequently

2. **Turn Processing** (Moderate)
   - ~20M combinations
   - ~15-30 minutes
   - Progress updates every few seconds

3. **Flop Processing** (Slow)
   - ~2.6M combinations
   - ~1-3 hours (most of the time)
   - May appear frozen at 0% initially
   - First progress after ~1-2 minutes

## Advanced Features of Safe Script

### 🔄 Automatic Resume Capability

The safe script (`generate_texas_holdem_lut_safe.sh`) includes intelligent resume:

```bash
# Check what stages are already complete
./generate_texas_holdem_lut_safe.sh standard status

# Output example:
# ✅ Completed stages: pre_flop river turn
# ⏳ Remaining: flop

# Resume from where it left off
./generate_texas_holdem_lut_safe.sh standard resume
```

**How it works**:
1. Saves checkpoint after each stage (preflop, river, turn, flop)
2. On resume, detects completed stages and skips them
3. Automatically backs up existing files before retrying

### 🔁 Automatic Retry on Failure

The script will automatically retry up to 3 times if generation fails:
- Attempt 1: Initial run
- Attempt 2: Check for partial progress and resume
- Attempt 3: Final attempt with fresh start if needed

### 📊 Real-time Resource Monitoring

The safe script monitors system resources every 30 seconds:
- Shows memory usage during generation
- Helps identify resource constraints
- Runs in background without interfering

### 🗄️ Automatic Backup

Before starting or retrying, the script:
1. Backs up existing `card_info_lut.joblib` with timestamp
2. Backs up `centroids.joblib` if present
3. Preserves checkpoint files
4. Names backups with format: `card_info_lut_YYYYMMDD_HHMMSS.joblib.bak`

### 📝 Descriptive Output Files

After successful generation, creates:
- `card_info_lut.joblib` - Main file
- `texas_holdem_[mode]_lut.joblib` - Descriptive copy
- `checkpoint_*.joblib` - Stage checkpoints
- `centroids.joblib` - Cluster centers

## Troubleshooting

### "Frozen at 0%" Issue

This is normal for flop processing! The code processes in chunks:
- We've optimized chunk sizes for better progress visibility
- First update appears after 1-2 minutes
- Progress then updates regularly

### Out of Memory

If you run out of memory:
1. Reduce clusters: Use test mode
2. Reduce simulations: Modify the script
3. Close other applications
4. Use a machine with more RAM (16GB+ recommended)

### Interrupted Generation

With the safe script, interruptions are handled gracefully:
- **Automatic checkpoints**: Saves after each stage
- **Smart resume**: Detects and continues from last checkpoint
- **No lost work**: All completed stages are preserved

```bash
# If generation is interrupted (Ctrl+C, crash, etc.)
# Simply run:
./generate_texas_holdem_lut_safe.sh standard resume

# The script will:
# 1. Check existing progress
# 2. Skip completed stages
# 3. Continue from where it stopped
```

### Corrupted Files

If the LUT file becomes corrupted:
```bash
# Check file integrity
./generate_texas_holdem_lut_safe.sh standard status

# If corrupted, the script will:
# 1. Detect the corruption
# 2. Backup the corrupted file
# 3. Offer to restart fresh
```

## Advanced Configuration

### Custom Parameters

```bash
uv run poker_ai cluster \
    --low_card_rank 2 \
    --high_card_rank 14 \
    --n_river_clusters 300 \
    --n_turn_clusters 300 \
    --n_flop_clusters 300 \
    --n_simulations_river 15 \
    --n_simulations_turn 15 \
    --n_simulations_flop 15 \
    --save_dir .
```

### Parameter Guidelines

**Clusters**: More clusters = better strategy approximation
- Minimum: 50 (testing only)
- Standard: 200 (good balance)
- Professional: 500+ (diminishing returns above 1000)

**Simulations**: More simulations = better accuracy
- Minimum: 5 (fast but noisy)
- Standard: 10 (good balance)
- High: 20+ (slow but accurate)

## Files Generated

After successful generation:
- `card_info_lut.joblib` - Main lookup table
- `centroids.joblib` - Cluster centers for each stage
- `texas_holdem_[mode]_lut.joblib` - Backup with descriptive name

## Using the LUT

### Generate Once, Use Everywhere! 🎯

**Important**: You only need to generate the LUT once! It can be reused:
- On different machines
- For multiple training runs
- By different team members
- Across different operating systems

```bash
# Generate on powerful machine (ONCE)
./generate_texas_holdem_lut_safe.sh high  # 6-10 hours, best quality

# Copy to other machines
scp card_info_lut.joblib user@laptop:~/poker_ai/
scp card_info_lut.joblib user@server:~/poker_ai/

# Use everywhere (MANY TIMES)
./train_ai.sh medium  # Uses the LUT, doesn't modify it
```

### Sharing LUTs

**Best Practices**:
1. Generate on your most powerful machine
2. Use high quality mode for production
3. Version your LUT files
4. Share via cloud storage or Git LFS
5. Document generation parameters

```bash
# Version naming example
mv card_info_lut.joblib texas_holdem_v1_high_200clusters_2024.joblib
```

### In Training
```bash
# The training scripts automatically look for card_info_lut.joblib
./train_ai.sh medium
```

### In Code
```python
import joblib

# Load the LUT
card_info_lut = joblib.load('card_info_lut.joblib')

# Use in game state
from poker_ai.games.texas_holdem.state import new_game
state = new_game(n_players=3, card_info_lut=card_info_lut)
```

## Performance Optimizations

The clustering code has been optimized for:
1. **Better parallelization**: Uses optimal worker count
2. **Smaller chunks**: More frequent progress updates
3. **Progress visibility**: Descriptive progress bars
4. **Memory efficiency**: Processes in batches

## LUT Determinism and Variance

### Are LUTs Identical Each Time?

**No**, each generation produces a slightly different LUT due to:
- Random Monte Carlo sampling
- K-means random initialization
- Random opponent hand simulations

### Does It Matter?

**For most users: NO**
- Variance is small (±1-2% in strategy quality)
- All LUTs with same parameters are equivalently good
- Like different poker pros with different styles

**For researchers: MAYBE**
- Need reproducible results? Set random seeds
- Comparing algorithms? Use deterministic mode
- Production use? Variance is actually beneficial

### Making LUTs Deterministic

If you need identical LUTs:
```python
# In card_info_lut_builder.py __init__:
import numpy as np
np.random.seed(42)  # Fixed seed

# In cluster() method:
km = KMeans(
    n_clusters=num_clusters,
    init="k-means++",
    n_init=1,  # Single run
    random_state=42  # Fixed seed
)
```

## Best Practices for Safe LUT Generation

### Why Use the Safe Script?

The `generate_texas_holdem_lut_safe.sh` script is superior because:

| Feature | Regular Script | Safe Script |
|---------|---------------|-------------|
| Resume on crash | ❌ Start over | ✅ Continue from checkpoint |
| Automatic retry | ❌ Manual restart | ✅ Up to 3 attempts |
| Progress checking | ❌ Guess based on time | ✅ `status` command |
| Resource monitoring | ❌ None | ✅ Memory usage display |
| File backup | ❌ Manual | ✅ Automatic with timestamp |
| Corruption handling | ❌ Manual detection | ✅ Auto-detect and backup |

### When to Use Each Script

**Use Safe Script for**:
- Production LUT generation
- Long-running high-quality modes
- Unreliable systems or remote servers
- When you can't monitor continuously
- First-time generation

**Use Regular Script for**:
- Quick test runs you're actively monitoring
- When you need custom parameters
- Debugging the clustering algorithm

## Recommendations

1. **Always use safe script**: `generate_texas_holdem_lut_safe.sh` for reliability
2. **For Development**: Use test mode (fast, good enough for testing)
3. **For Training**: Use standard mode (balanced quality/time)
4. **For Competition**: Use high mode (maximum quality)
5. **Generate Once**: Create LUT on best machine, use everywhere
6. **Check Status First**: Run `status` before starting to see if work exists
7. **Monitor Progress**: Watch memory usage in the script output
8. **Be Patient**: Flop processing takes time but will complete
9. **Trust the Resume**: If interrupted, just run with `resume`

## Next Steps

After generating the LUT:
1. Run training: `./train_ai.sh medium`
2. Test the AI: `uv run test_slumbot.py`
3. Play against it: `uv run poker_ai play`