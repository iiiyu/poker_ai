# Poker AI Training Guide

## Overview
This guide explains how to use the `zig build train` command to train the poker AI using Monte Carlo Counterfactual Regret Minimization (MCCFR) with Linear CFR optimizations.

## Prerequisites
- Zig 0.15.1 installed
- Project built successfully with `zig build`
- Sufficient RAM (2-8 GB depending on configuration)
- Multi-core CPU recommended for parallel training

## Basic Usage

```bash
# Run with default settings
zig build train

# Run with custom parameters
zig build train -- --iterations 1000000 --threads 16 --output-dir ./models
```

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--iterations <n>` | Number of MCCFR training iterations | 100,000 |
| `--threads <n>` | Number of parallel worker threads | 8 |
| `--players <n>` | Number of players (2-6) | 2 |
| `--output-dir <path>` | Directory to save strategy files | ./strategies |
| `--no-linear-cfr` | Disable Linear CFR optimizations | false (enabled) |
| `--quiet` | Disable progress output | false (show progress) |
| `--help` | Show help message | - |

## Generated Files

### Output Structure
```
strategies/                           # Default output directory
├── strategy_checkpoint_5000.strat   # Checkpoint at 5k iterations
├── strategy_checkpoint_10000.strat  # Checkpoint at 10k iterations
├── strategy_checkpoint_15000.strat  # Checkpoint at 15k iterations
├── ...                              # More checkpoints every 5k
└── strategy_final.strat             # Final strategy after all iterations
```

### File Format (.strat)
Binary format containing:
- **Header**: "POKERSTRAT" magic string
- **Version**: Format version (currently 1)
- **Information Sets**: Compressed strategy data
  - Hash keys for game states
  - Average strategy probabilities
  - Regret values
  - Visit counts
  - Update timestamps

## Example Training Sessions

### Quick Test Run
```bash
# 100k iterations for testing
zig build train
```

### Production Training
```bash
# 10 million iterations with 16 threads
zig build train -- --iterations 10000000 --threads 16
```

### Multi-Player Games
```bash
# 6-player game with 5M iterations
zig build train -- --players 6 --iterations 5000000
```

### Custom Output Directory
```bash
# Save to specific directory
zig build train -- --output-dir ./trained_models --iterations 1000000
```

### Background Training
```bash
# Quiet mode for running in background
zig build train -- --quiet --iterations 10000000 > training.log 2>&1 &
```

### Utilizing All CPU Cores
```bash
# Automatically use all available cores
zig build train -- --threads $(nproc) --iterations 5000000
```

## Training Process

### 1. Initialization Phase
- Allocates memory for information sets
- Initializes game tree structure
- Sets up parallel worker threads
- Creates output directory if needed

### 2. MCCFR Iterations
- Samples game trajectories using Monte Carlo
- Updates regrets for each information set
- Applies regret matching to compute strategies
- Uses Linear CFR discounting for faster convergence

### 3. Progress Monitoring
During training, you'll see:
```
[INFO] Iteration 50000/100000 (50.00%) - 2500 iter/sec - Time: 00:00:20
[INFO] Exploitability: 0.042831 mbb/hand (best: 0.042831)
[INFO] Information sets: 125,432
[INFO] Memory usage: 48.23 MB
```

### 4. Checkpointing
- Saves strategy every 5,000 iterations
- Allows resuming from checkpoints if interrupted
- Keeps best strategy based on exploitability

### 5. Final Output
Upon completion:
```
[INFO] Training completed!
[INFO] Total iterations: 100000
[INFO] Final exploitability: 0.021543 mbb/hand
[INFO] Information sets: 287,654
[INFO] Total actions stored: 1,438,270
[INFO] Average actions per InfoSet: 5.00
[INFO] Actual memory usage: 112.45 MB
[INFO] Strategy saved to: ./strategies/strategy_final.strat
```

## Memory Requirements

### By Player Count
| Players | Minimum RAM | Recommended RAM | Typical File Size |
|---------|------------|-----------------|-------------------|
| 2 | 512 MB | 2 GB | 50-200 MB |
| 3 | 1 GB | 4 GB | 200-500 MB |
| 4 | 2 GB | 6 GB | 500 MB - 1 GB |
| 5 | 3 GB | 8 GB | 1-2 GB |
| 6 | 4 GB | 10 GB | 2-3 GB |

### Factors Affecting Memory
- Number of iterations (more iterations = more information sets discovered)
- Game complexity (betting rounds, stack sizes)
- Number of players
- Thread count (each thread needs working memory)

## Convergence Guidelines

### Iteration Recommendations
| Game Type | Minimum | Good | Excellent |
|-----------|---------|------|-----------|
| 2-player Heads-up | 100k | 1M | 10M+ |
| 3-player | 500k | 5M | 50M+ |
| 4-player | 1M | 10M | 100M+ |
| 5-player | 2M | 20M | 200M+ |
| 6-player | 5M | 50M | 500M+ |

### Monitoring Convergence
Good convergence indicators:
- Exploitability < 0.05 mbb/hand (2-player)
- Exploitability < 0.1 mbb/hand (6-player)
- Strategy changes < 0.001 between checkpoints
- Consistent decrease in exploitability

## Using Trained Strategies

### Loading Strategy Files
```zig
// In your Zig code
const strategy = try loadStrategy(allocator, "./strategies/strategy_final.strat");
defer strategy.deinit();
```

### Integration with Game
The trained strategies can be used for:
- Playing against human opponents
- Analyzing optimal play lines
- Generating training data
- Evaluating other strategies

### Strategy Analysis
You can analyze the generated strategies using:
- The included analysis tools
- Export to common poker solver formats
- Visualization of strategy frequencies

## Troubleshooting

### Common Issues

#### Out of Memory
**Solution**: Reduce threads or use checkpoints
```bash
zig build train -- --threads 4 --iterations 1000000
```

#### Slow Training
**Solution**: Enable Linear CFR (default) and use more threads
```bash
zig build train -- --threads $(nproc)
```

#### Training Interrupted
**Solution**: Implement checkpoint loading (future feature)
```bash
# Currently need to restart, checkpoint loading coming soon
zig build train -- --iterations 1000000
```

#### High Exploitability
**Solution**: More iterations needed
```bash
zig build train -- --iterations 10000000
```

## Advanced Configuration

### Custom Training Parameters
Edit `src/train.zig` to modify:
- `checkpoint_interval`: How often to save (default: 5000)
- `discount_interval`: Linear CFR discount frequency (default: 1000)
- `exploration_epsilon`: Exploration parameter (default: 0.6)
- `exploitability_interval`: How often to calculate exploitability (default: 10000)

### Parallel Training Settings
For optimal performance:
```bash
# Set thread count to physical cores (not hyperthreads)
zig build train -- --threads $(lscpu | grep "^Core(s)" | awk '{print $4}')
```

### Memory Optimization
To reduce memory usage:
1. Use fewer threads
2. Save checkpoints more frequently
3. Implement pruning (requires code modification)
4. Use smaller stack sizes in game configuration

## Performance Tips

### CPU Optimization
1. **Use Physical Cores**: Set threads to physical core count, not logical
2. **NUMA Awareness**: On multi-socket systems, pin to single NUMA node
3. **CPU Governor**: Set to performance mode
   ```bash
   sudo cpupower frequency-set -g performance
   ```

### Memory Optimization
1. **Huge Pages**: Enable transparent huge pages
   ```bash
   echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
   ```
2. **Swap**: Ensure sufficient swap space for large training runs
3. **Memory Allocation**: Use jemalloc for better performance (future feature)

### Storage Optimization
1. **SSD**: Use SSD for output directory
2. **Compression**: Strategy files are not compressed by default
3. **Cleanup**: Remove old checkpoints to save space

## Interpreting Results

### Exploitability
- **< 0.01 mbb/hand**: Near-optimal play
- **0.01-0.05 mbb/hand**: Very strong play
- **0.05-0.1 mbb/hand**: Good play
- **> 0.1 mbb/hand**: Needs more training

### Information Sets
- More information sets = more game situations covered
- Growth rate slows as training progresses
- Typical counts:
  - 2-player: 100k-500k sets
  - 6-player: 1M-10M sets

### Convergence Rate
- Fast initial improvement (first 10% of iterations)
- Slower refinement phase (remaining 90%)
- Diminishing returns after convergence

## Next Steps

After training completes:
1. **Test the Strategy**: Use the play mode to test against the AI
2. **Analyze Performance**: Review exploitability and strategy statistics
3. **Fine-tune**: Adjust parameters and retrain if needed
4. **Deploy**: Integrate the strategy into your application

## Additional Resources

- [MCCFR Algorithm Paper](https://papers.nips.cc/paper/2009/hash/00411460f7c92d2124a67ea0f4cb5f85-Abstract.html)
- [Linear CFR Paper](https://arxiv.org/abs/1809.04040)
- [Poker AI Research](https://www.cs.cmu.edu/~noamb/papers/17-Science-Libratus.pdf)

## Support

For issues or questions:
- Check the troubleshooting section above
- Review the source code in `src/train.zig`
- Open an issue on the project repository