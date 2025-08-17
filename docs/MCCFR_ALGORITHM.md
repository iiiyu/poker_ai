# Monte Carlo Counterfactual Regret Minimization (MCCFR) Algorithm

## Overview

MCCFR is the core algorithm that powers this poker AI. It learns optimal strategies by playing millions of hands against itself, tracking regrets (missed opportunities), and adjusting its strategy to minimize those regrets over time.

## Key Concepts

### 1. Information Sets
An **information set** represents all game states that look identical to a player given their private information.

Example:
- You hold: A♠ K♥
- Community cards: Q♦ J♣ 10♠
- Your information set includes your cards + public cards, but NOT opponent cards

### 2. Regret
**Regret** measures how much a player wishes they had taken a different action.

```
Regret = Value(best_action) - Value(action_taken)
```

If you folded with AA and would have won $1000, your regret is $1000.

### 3. Strategy
A **strategy** is a probability distribution over actions at each information set.

Example strategy:
- Check: 20%
- Bet small: 50%
- Bet large: 30%

### 4. Counterfactual Value
The expected value of reaching a game state, weighted by the probability that opponents play to reach it (but NOT weighted by our own probability).

## The MCCFR Algorithm

### Core Loop (Simplified)

```python
def mccfr(iterations):
    regrets = {}      # Cumulative regrets for each action
    strategy = {}     # Average strategy over all iterations
    
    for i in range(iterations):
        # Sample random cards for all players
        cards = deal_cards()
        
        # Traverse game tree from root
        for player in players:
            traverse(root_state, player, cards)
        
        # Update average strategy
        update_strategy()
```

### Traversal Function

The heart of MCCFR is the recursive traversal:

```python
def traverse(state, traversing_player, cards):
    if state.is_terminal():
        return state.payoff(traversing_player)
    
    if state.current_player == traversing_player:
        # We're acting - explore all actions
        values = {}
        for action in state.legal_actions:
            new_state = state.apply_action(action)
            values[action] = traverse(new_state, traversing_player, cards)
        
        # Calculate regrets and update strategy
        info_set = state.info_set(traversing_player)
        update_regrets(info_set, values)
        
        # Return weighted average value
        return sum(strategy[info_set][a] * values[a] for a in actions)
    
    elif state.current_player == CHANCE:
        # Chance node (dealing cards)
        # Already sampled in MCCFR
        return traverse(state.deal_cards(cards), traversing_player, cards)
    
    else:
        # Opponent acting - sample one action
        action = sample_action(state, state.current_player)
        new_state = state.apply_action(action)
        return traverse(new_state, traversing_player, cards)
```

## Implementation Details

### 1. State Representation (`poker_ai/games/texas_holdem/state.py`)

The `TexasHoldemPokerState` class is immutable and supports:
- Efficient cloning for tree traversal
- Information set calculation
- Legal action generation
- Terminal value computation

Key methods:
```python
class TexasHoldemPokerState:
    def apply_action(self, action: str) -> TexasHoldemPokerState:
        """Returns new state after action"""
        
    def info_set(self, player: int) -> str:
        """Returns information set ID for player"""
        
    def is_terminal(self) -> bool:
        """Check if hand is over"""
        
    def payoff(self, player: int) -> float:
        """Return player's winnings/losses"""
```

### 2. MCCFR Implementation (`poker_ai/ai/ai.py`)

The actual implementation includes optimizations:

#### a. CFR with Pruning (CFR-P)
Skips traversing actions with very negative regret:

```python
def cfrp(state, player, prune_threshold=-300):
    # Skip if regret below threshold
    if regret[info_set][action] < prune_threshold:
        continue  # Don't traverse this action
```

#### b. Sampling Variants
- **External Sampling**: Sample cards for all players except traverser
- **Outcome Sampling**: Sample everything including traverser's actions
- **Chance Sampling**: Sample chance events but not player actions

Our implementation uses External Sampling for efficiency.

#### c. Strategy Updates

Regret Matching Formula:
```python
def get_strategy(info_set):
    regrets = cumulative_regrets[info_set]
    
    # Regret matching
    positive_regrets = max(0, regrets)
    sum_positive = sum(positive_regrets)
    
    if sum_positive > 0:
        strategy = positive_regrets / sum_positive
    else:
        strategy = uniform_distribution()
    
    return strategy
```

Average Strategy Update:
```python
def update_average_strategy(info_set, current_strategy, weight):
    for action in actions:
        strategy_sum[info_set][action] += weight * current_strategy[action]
```

### 3. Information Set Abstraction

Texas Hold'em has ~10^14 information sets - too many to store. We use abstraction:

#### Card Clustering
Groups similar hands together:
```python
# Instead of storing:
info_sets["Ah Kh | Qd Jc 10s"] = strategy1
info_sets["As Ks | Qd Jc 10s"] = strategy2  # Very similar!

# We store:
info_sets["cluster_15 | cluster_201"] = strategy  # One strategy for similar hands
```

#### Abstraction Levels
1. **Preflop**: 169 clusters (exact - no abstraction needed)
2. **Flop**: ~200 clusters (from 1.3M combinations)
3. **Turn**: ~200 clusters (from 60M combinations)
4. **River**: ~200 clusters (from 2.6B combinations)

### 4. Storage Optimization

Strategies are stored in compressed dictionaries:
```python
# Strategy storage structure
{
    "info_set_id": {
        "fold": 0.2,
        "call": 0.5,
        "raise": 0.3
    },
    ...
}

# Compressed with gzip
# Sparse storage (only non-zero values)
# Periodic pruning of unused info sets
```

## Training Process

### 1. Initialization
```python
# Create initial game state
state = new_game(n_players=3)

# Initialize strategy to uniform
strategy = defaultdict(lambda: uniform_distribution())

# Initialize regrets to zero
regrets = defaultdict(lambda: defaultdict(float))
```

### 2. Main Training Loop
```python
def train(iterations=1_000_000):
    for i in range(iterations):
        # Alternate update player
        traverser = i % n_players
        
        # Run MCCFR iteration
        mccfr_iteration(traverser)
        
        # Save periodically
        if i % save_interval == 0:
            save_strategy(f"strategy_{i}.pkl")
        
        # Prune negative regrets (CFR+)
        if i % prune_interval == 0:
            prune_regrets()
```

### 3. Convergence

MCCFR converges to Nash Equilibrium (optimal play) given:
- Sufficient iterations (millions)
- All information sets visited
- Proper regret updates

Convergence rate: O(1/√iterations)

## Optimizations in Our Implementation

### 1. Multiprocessing (`poker_ai/ai/multiprocess/`)
- Distributes MCCFR iterations across CPU cores
- Synchronizes strategies periodically
- 2-3x speedup on multi-core machines

### 2. Memory Management
- Lazy initialization of dictionaries
- Periodic garbage collection
- Strategy compression

### 3. Pruning Strategies
- CFR+ (reset negative regrets)
- CFR-P (don't traverse bad actions)
- Linear discounting of old regrets

### 4. Efficient State Representation
- Immutable states (no deep copies needed)
- Cached legal actions
- Pre-computed hand evaluations

## Example MCCFR Iteration

Let's trace through one iteration:

```python
# Iteration 50,000, Player 0 traversing
# Dealt: Player 0: [A♠ K♠], Player 1: [Q♥ Q♦], Player 2: [7♣ 2♦]

1. Preflop:
   - P1 posts small blind $50
   - P2 posts big blind $100
   - P0 to act: info_set = "AKs"
   - Current strategy: {fold: 0.1, call: 0.3, raise: 0.6}
   - Traverse all actions:
     * fold → value = -$0
     * call → value = -$100 (loses to QQ)
     * raise → value = +$200 (others fold)
   - Regret: call = -100, raise = +100
   - Update cumulative regrets

2. If P0 raises:
   - P1 to act: info_set = "QQ | opponent_raised"
   - Sample P1's action based on strategy
   - P1 calls (sampled)
   
3. Continue until terminal...
   - Showdown: QQ wins
   - P0 payoff: -$500
   
4. Backpropagate values and update regrets
```

## Key Parameters

### Training Parameters
- **Iterations**: 100K (test) to 10M+ (production)
- **Save Interval**: Every 10K-100K iterations
- **Prune Threshold**: -300 to -1000
- **Discount Factor**: 0.999 (for CFR+)

### Game Parameters
- **Players**: 2-6 (3 is default)
- **Starting Stack**: 20,000 chips
- **Blinds**: 50/100

## Why MCCFR Works

1. **Explores All Strategies**: Unlike neural nets, explicitly tries all actions
2. **Theoretically Sound**: Proven convergence to Nash Equilibrium
3. **No Training Data Needed**: Learns purely from self-play
4. **Handles Imperfect Information**: Core design for hidden information games
5. **Scalable**: Can be distributed across many machines

## Limitations

1. **Memory Intensive**: Stores strategies for millions of info sets
2. **Slow Convergence**: Needs millions of iterations
3. **Requires Abstraction**: Can't handle full game complexity
4. **Fixed Opponents**: Assumes opponents play optimally

## Further Reading

- Original CFR paper: Zinkevich et al. (2008)
- Monte Carlo CFR: Lanctot et al. (2009)
- CFR+: Tammelin et al. (2015)
- Pluribus/Libratus: Brown & Sandholm (2017-2019)