# Clustering and LUT Generation Guide

## Overview

The Card Information Lookup Table (LUT) is essential for poker AI training. It groups similar card combinations into clusters to make the game computationally tractable. Without clustering, Texas Hold'em has over 10^14 possible card combinations, which is impossible to handle directly.

## Quick Start

### Generate Standard Quality LUT (Recommended)
```bash
./generate_texas_holdem_lut.sh standard
```
- Time: 2-4 hours
- Size: ~300-400MB
- Quality: Good for competitive play

### Generate Test LUT (For Development)
```bash
./generate_texas_holdem_lut.sh test
```
- Time: 30-60 minutes
- Size: ~150-200MB
- Quality: Sufficient for testing

### Generate High Quality LUT (For Production)
```bash
./generate_texas_holdem_lut.sh high
```
- Time: 6-10 hours
- Size: ~500-700MB
- Quality: Professional level

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

The process saves progress after each stage:
- River completes → saved
- Turn completes → saved
- Flop completes → saved

You can potentially resume, but it's usually better to restart.

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

## Recommendations

1. **For Development**: Use test mode (fast, good enough for testing)
2. **For Training**: Use standard mode (balanced quality/time)
3. **For Competition**: Use high mode (maximum quality)
4. **Monitor Progress**: Always run monitor_clustering.py
5. **Be Patient**: Flop processing takes time but will complete

## Next Steps

After generating the LUT:
1. Run training: `./train_ai.sh medium`
2. Test the AI: `uv run test_slumbot.py`
3. Play against it: `uv run poker_ai play`