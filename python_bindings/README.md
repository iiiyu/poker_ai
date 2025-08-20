# Python Bindings for Zig Poker AI

This package provides high-performance Python bindings for the Zig poker AI library, enabling seamless integration of the memory-efficient Zig backend with existing Python codebases.

## Features

- **High Performance**: 5-10x speed improvement over pure Python implementation
- **Memory Efficient**: 10x reduction in memory usage (5GB+ → 500MB)
- **Drop-in Replacement**: Compatible with existing Python poker AI interfaces
- **Type Safety**: Comprehensive type hints and error handling
- **Async Support**: Both synchronous and asynchronous training interfaces
- **Cross-Platform**: Works on macOS, Linux, and Windows

## Installation

### Prerequisites

1. **Zig Compiler**: Install Zig 0.14+ from [ziglang.org](https://ziglang.org)
2. **SQLite**: Required for clustering and strategy storage
3. **Python Dependencies**: numpy, typing_extensions

### Build the Zig Library

```bash
cd poker_ai/zig
zig build
```

This creates the shared library at `zig-out/lib/libpoker_ai.dylib` (macOS) or equivalent for your platform.

### Install Python Dependencies

```bash
pip install numpy typing_extensions
# Optional: joblib for Python strategy compatibility
pip install joblib
```

## Quick Start

### Basic Hand Evaluation

```python
from poker_ai.python_bindings import HandEvaluator, card_from_rank_suit

# Create evaluator
evaluator = HandEvaluator()

# Create cards (rank 0-12, suit 0-3)
cards = [
    card_from_rank_suit(12, 0),  # Ace of spades
    card_from_rank_suit(11, 0),  # King of spades  
    card_from_rank_suit(10, 0),  # Queen of spades
    card_from_rank_suit(9, 0),   # Jack of spades
    card_from_rank_suit(8, 0),   # 10 of spades
]

# Evaluate hand (higher is better)
score = evaluator.evaluate_5(cards)
print(f"Hand score: {score}")  # Should be very high (royal flush)
```

### Game State Management

```python
from poker_ai.python_bindings import GameState, ActionType

# Create a 4-player game
game = GameState(num_players=4, small_blind=10, big_blind=20)

# Deal hole cards to players
game.deal_hole_cards(0, card_from_rank_suit(12, 0), card_from_rank_suit(12, 1))  # Pocket aces
game.deal_hole_cards(1, card_from_rank_suit(11, 2), card_from_rank_suit(11, 3))  # Pocket kings

# Apply actions
game.apply_action(ActionType.RAISE, 60)  # Player raises to 60
game.apply_action(ActionType.CALL, 60)   # Next player calls

# Check game state
print(f"Current pot: {game.pot}")
print(f"Current player: {game.current_player}")
print(f"Is terminal: {game.is_terminal()}")
```

### Training with High-Level Interface

```python
from poker_ai.python_bindings import TrainingConfig, ZigTrainingInterface

# Configure training
config = TrainingConfig(
    iterations=10000,
    num_threads=4,
    checkpoint_interval=1000,
    save_interval=2000,
    strategy_save_path="my_strategy.zig"
)

# Create trainer
trainer = ZigTrainingInterface(config)

# Train synchronously with progress tracking
def progress_callback(progress):
    print(f"Iteration {progress.current_iteration}/{progress.total_iterations} "
          f"({progress.iterations_per_second:.1f} it/s)")

result = trainer.train_sync(progress_callback)
print(f"Training completed in {result.elapsed_time:.2f} seconds")
```

### Async Training

```python
import asyncio
from poker_ai.python_bindings import TrainingConfig, ZigTrainingInterface

async def train_async_example():
    config = TrainingConfig(iterations=5000, num_threads=2)
    trainer = ZigTrainingInterface(config)
    
    # Train asynchronously
    result = await trainer.train_async()
    print(f"Async training completed: {result.current_iteration} iterations")

# Run the async training
asyncio.run(train_async_example())
```

### Compatibility Mode (Drop-in Replacement)

```python
from poker_ai.python_bindings import CompatibilityTrainer

# Use Python-style configuration
config = {
    'iterations': 1000,
    'n_jobs': 4,           # Maps to num_threads
    'verbose': True,       # Enable progress display
    'save_path': 'strategy.joblib'  # Will be converted to/from Zig format
}

# Train with Python-compatible interface
trainer = CompatibilityTrainer(config)
result = trainer.train()

print(f"Training completed: {result['iterations_completed']} iterations")
print(f"Speed: {result['iterations_per_second']:.1f} it/s")

# Save in Python format (joblib/pickle/json)
trainer.save('my_strategy.joblib', format='joblib')
```

## Advanced Usage

### Strategy Format Conversion

```python
from poker_ai.python_bindings import get_strategy_loader, StrategyFormat

loader = get_strategy_loader()

# Convert existing Python strategy to Zig format
loader.convert_python_to_zig(
    python_strategy_dict,
    'strategy.zig'
)

# Convert Zig strategy back to Python
python_strategy = loader.convert_zig_to_python(
    'strategy.zig',
    'strategy.joblib',
    StrategyFormat.JOBLIB
)

# Check compatibility between formats
compatibility = loader.check_compatibility('old_strategy.joblib', 'new_strategy.zig')
print(f"Compatibility score: {compatibility['compatibility_score']:.2f}")
```

### Memory Management

```python
from poker_ai.python_bindings import poker_ai_context

# Use context manager for automatic cleanup
with poker_ai_context():
    evaluator = HandEvaluator()
    game = GameState(num_players=6, small_blind=5, big_blind=10)
    
    # Do work...
    score = evaluator.evaluate_5(cards)
    
# Resources automatically cleaned up here
```

### Game State Conversion

```python
from poker_ai.python_bindings import (
    get_converter, PythonGameState, PlayerState, GamePhase, ActionType
)

converter = get_converter()

# Create Python game state
players = [
    PlayerState(
        chips=1000,
        committed=20,
        hole_cards=((12, 'spades'), (11, 'hearts')),  # A♠ K♥
        is_active=True,
        is_folded=False
    ),
    PlayerState(
        chips=2000,
        committed=10, 
        hole_cards=((10, 'diamonds'), (9, 'clubs')),  # Q♦ J♣
        is_active=True,
        is_folded=False
    ),
]

game_state = PythonGameState(
    num_players=2,
    current_player=0,
    dealer_button=1,
    small_blind=10,
    big_blind=20,
    pot=30,
    phase=GamePhase.PREFLOP,
    community_cards=[],
    players=players,
    action_history=[(0, ActionType.RAISE, 20)]
)

# Convert to Zig-compatible format
zig_data = converter.gamestate_to_zig_compatible(game_state)

# Convert back to Python
restored_state = converter.gamestate_from_zig_compatible(zig_data)
```

### Batch Training

```python
from poker_ai.python_bindings import BatchTrainingManager, TrainingConfig

# Create multiple training jobs
manager = BatchTrainingManager()

configs = [
    TrainingConfig(iterations=1000, num_threads=2, strategy_save_path=f"strategy_{i}.zig")
    for i in range(3)
]

for i, config in enumerate(configs):
    manager.add_job(f"job_{i}", config)

# Run all jobs with limited concurrency
results = manager.run_batch_sync(max_concurrent=2)

for job_id, result in results.items():
    print(f"{job_id}: {result.current_iteration} iterations completed")
```

## Performance Comparison

### Hand Evaluation Benchmark

```python
import time
import numpy as np
from poker_ai.python_bindings import HandEvaluator

evaluator = HandEvaluator()

# Generate 10,000 random hands
hands = []
for i in range(10000):
    hand = [i % 52, (i + 1) % 52, (i + 2) % 52, (i + 3) % 52, (i + 4) % 52]
    hands.append(hand)

# Time the evaluation
start_time = time.time()
for hand in hands:
    score = evaluator.evaluate_5(hand)
end_time = time.time()

evaluations_per_second = len(hands) / (end_time - start_time)
print(f"Zig evaluator: {evaluations_per_second:.0f} evaluations/second")
```

Expected performance (M1 Mac):
- **Zig implementation**: ~500,000 evaluations/second
- **Python implementation**: ~50,000 evaluations/second
- **Speedup**: ~10x

### Memory Usage Comparison

```python
import psutil
import os
from poker_ai.python_bindings import CFRTrainer

# Monitor memory usage
process = psutil.Process(os.getpid())
initial_memory = process.memory_info().rss / 1024 / 1024  # MB

# Create trainer and train
trainer = CFRTrainer(iterations=1000, num_threads=1)
trainer.train()

final_memory = process.memory_info().rss / 1024 / 1024  # MB
print(f"Memory usage: {final_memory - initial_memory:.1f} MB")
```

Expected memory usage:
- **Zig implementation**: ~50-500 MB
- **Python implementation**: ~1-5 GB
- **Reduction**: ~10x

## Error Handling

The bindings provide comprehensive error handling:

```python
from poker_ai.python_bindings import (
    HandEvaluator, GameState, InvalidParameterError, 
    AllocationError, GameStateError
)

try:
    # This will raise InvalidParameterError
    game = GameState(num_players=1, small_blind=10, big_blind=20)
except InvalidParameterError as e:
    print(f"Invalid parameter: {e}")

try:
    evaluator = HandEvaluator()
    # This will raise InvalidParameterError (wrong number of cards)
    evaluator.evaluate_5([1, 2, 3])
except InvalidParameterError as e:
    print(f"Hand evaluation error: {e}")

try:
    # This will raise FileError if file doesn't exist
    strategy_table = StrategyTable()
    strategy_table.load("/nonexistent/file.zig")
except FileError as e:
    print(f"File error: {e}")
```

## Testing

Run the comprehensive test suite:

```bash
cd python_bindings
python -m pytest tests/ -v
```

Or run specific test categories:

```bash
# Test basic functionality
python tests/test_bindings.py TestZigLibraryBasics

# Test hand evaluation
python tests/test_bindings.py TestHandEvaluator

# Test training interface
python tests/test_bindings.py TestTrainingInterface

# Test performance
python tests/test_bindings.py TestPerformance
```

## Troubleshooting

### Library Not Found

If you get "library not found" errors:

1. Check that the Zig library was built: `ls zig/zig-out/lib/`
2. Verify the library path in error messages
3. Try rebuilding: `cd zig && zig build --release=fast`

### Memory Issues

If you encounter memory problems:

1. Use context managers: `with poker_ai_context():`
2. Explicitly delete large objects: `del trainer`
3. Monitor memory usage with `psutil`
4. Reduce batch sizes or iteration counts

### Performance Issues

If performance is slower than expected:

1. Build with optimizations: `zig build --release=fast`
2. Use multiple threads: `num_threads=os.cpu_count()`
3. Profile with Python's `cProfile` module
4. Check system resource usage

### Compatibility Issues

If existing Python code doesn't work:

1. Use `CompatibilityTrainer` for drop-in replacement
2. Convert strategy formats with `StrategyLoader`
3. Check the compatibility guide in the docs
4. File an issue with code examples

## API Reference

### Core Classes

- `HandEvaluator`: Fast poker hand evaluation
- `GameState`: Game state management and action application
- `CFRTrainer`: Counterfactual regret minimization training
- `StrategyTable`: Strategy storage and retrieval

### Training Classes

- `TrainingConfig`: Training configuration
- `ZigTrainingInterface`: High-level training interface
- `CompatibilityTrainer`: Python-compatible training interface
- `BatchTrainingManager`: Multi-job training management

### Conversion Classes

- `GameStateConverter`: Convert between Python/Zig game states
- `StrategyLoader`: Load/save/convert strategy formats
- `NumpyArrayConverter`: Efficient numpy array transfer

### Utility Functions

- `get_version()`: Get Zig library version
- `poker_ai_context()`: Context manager for resource cleanup
- `card_from_rank_suit()`: Create card from rank/suit
- `card_get_rank()`, `card_get_suit()`: Extract card components

## Contributing

1. Follow the existing code style (Black formatting, type hints)
2. Add tests for new functionality
3. Update documentation
4. Ensure compatibility with existing Python interfaces

## License

This project is licensed under the MIT License - see the LICENSE file for details.