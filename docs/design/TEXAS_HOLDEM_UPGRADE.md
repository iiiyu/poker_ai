# Texas Hold'em Upgrade Documentation

## Overview

This codebase now focuses exclusively on Texas Hold'em Poker (52 cards) with support for 2-8 players. Short deck poker support has been removed to simplify the codebase and improve Texas Hold'em strategy quality.

## Key Changes

### 1. New Texas Hold'em Game State
- **Location**: `poker_ai/games/texas_holdem/`
- **Class**: `TexasHoldemPokerState`
- **Features**:
  - Full 52-card deck (ranks 2-14/Ace)
  - Supports 2-8 players (vs 2-6 for short deck)
  - Compatible with existing AI algorithms

### 2. Preflop Abstractions for 52 Cards
- **Location**: `poker_ai/clustering/preflop_texas_holdem.py`
- **Function**: `compute_preflop_lossless_abstraction_texas_holdem()`
- **Details**:
  - Handles 169 unique starting hands (vs 25 for short deck)
  - Categorizes as pocket pairs, suited, and unsuited hands
  - Efficient clustering for AI training

### 3. Extended Card Info LUT Builder
- **Location**: `poker_ai/clustering/card_info_lut_builder_extended.py`
- **Class**: `CardInfoLutBuilderExtended`
- **Features**:
  - Supports both `"short_deck"` and `"texas_holdem"` deck types
  - Separate file paths for each game type's lookup tables
  - Automatic selection of appropriate preflop abstractions

### 4. Default Clustering Parameters (Updated)
- **Location**: `poker_ai/clustering/runner.py`
- **New Defaults**:
  - Card ranks: 2-14 (full deck)
  - River/Turn/Flop clusters: 200 each
  - Simulations: 10 each
  - Expected LUT size: 300-400MB
  - Generation time: 2-4 hours

### 5. Optimized Training Scripts
- **Location**: Root directory
- **Scripts**:
  - `train_ai.sh` - Multiple training modes (test, quick, medium, long)
  - `generate_texas_holdem_lut.sh` - LUT generation with quality modes
  - `monitor_training.py` - Real-time training progress monitoring
  - `monitor_clustering.py` - Clustering progress monitoring

## Usage Examples

### Creating a Texas Hold'em Game
```python
from poker_ai.games.factory import create_poker_game

# Create an 8-player Texas Hold'em game
state = create_poker_game(
    game_type="texas_holdem",
    n_players=8,
    small_blind=50,
    big_blind=100
)

# Play a round
for _ in range(8):
    state = state.apply_action("call")
```

### Training AI for Texas Hold'em
```python
from poker_ai.games.factory import get_deck_configuration
from poker_ai.clustering.card_info_lut_builder_extended import CardInfoLutBuilderExtended

# Get deck configuration
config = get_deck_configuration("texas_holdem")

# Create LUT builder for Texas Hold'em
builder = CardInfoLutBuilderExtended(
    n_simulations_river=1000,
    n_simulations_turn=1000,
    n_simulations_flop=1000,
    low_card_rank=config["low_card_rank"],  # 2
    high_card_rank=config["high_card_rank"],  # 14 (Ace)
    save_dir="./texas_holdem_luts",
    deck_type="texas_holdem"
)

# Compute clusters (this will take significant time for 52 cards)
builder.compute(
    n_river_clusters=200,
    n_turn_clusters=200,
    n_flop_clusters=200
)
```

## Comparison: Short Deck vs Texas Hold'em

| Feature | Short Deck | Texas Hold'em |
|---------|------------|---------------|
| Cards | 20 (10-A) | 52 (2-A) |
| Max Players | 6 | 8 |
| Starting Hands | ~190 total | ~1326 total |
| Unique Hands | 25 | 169 |
| Memory Usage | ~1x | ~10x |
| Training Time | ~1x | ~10x |

## Backward Compatibility

All existing Short Deck code remains unchanged and functional:
- `ShortDeckPokerState` class still works as before
- Original preflop abstractions preserved
- Existing trained models remain valid

## File Structure

```
poker_ai/
├── games/
│   ├── short_deck/          # Original short deck implementation
│   │   ├── state.py
│   │   └── player.py
│   ├── texas_holdem/        # New Texas Hold'em implementation
│   │   ├── state.py
│   │   └── player.py
│   └── factory.py           # Factory for creating either game type
├── clustering/
│   ├── preflop.py          # Original short deck preflop
│   ├── preflop_texas_holdem.py  # New Texas Hold'em preflop
│   ├── card_info_lut_builder.py  # Original builder
│   └── card_info_lut_builder_extended.py  # Extended for both types
```

## Important Notes

1. **Memory Requirements**: Texas Hold'em requires significantly more memory due to the larger state space (52 cards vs 20 cards).

2. **Computation Time**: Training AI for Texas Hold'em takes approximately 10x longer than Short Deck due to the increased number of card combinations.

3. **Lookup Tables**: Texas Hold'em and Short Deck use separate lookup table files to avoid conflicts.

4. **Player Limits**: Texas Hold'em supports up to 8 players (standard for online poker), while Short Deck remains limited to 6 players.

## Testing

Run the validation script to verify the implementation:
```bash
python standalone_test.py
```

This will verify that all components are properly installed and configured.