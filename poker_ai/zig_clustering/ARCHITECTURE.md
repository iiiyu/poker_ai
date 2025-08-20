# Texas Hold'em Poker Engine & Clustering System Architecture

## 1. Core Game Engine Components

### 1.1 Card & Deck
```
Card:
  - rank: u8 (2-14, where 14 = Ace)
  - suit: u8 (0-3: Spades, Hearts, Diamonds, Clubs)
  - toInt(): Convert to integer for evaluation
  
Deck:
  - cards: [52]Card
  - shuffle(): Randomize deck
  - deal(): Get next card
  - reset(): Restore all cards
```

### 1.2 Player
```
Player:
  - id: u32
  - hole_cards: [2]Card
  - chips: i64
  - current_bet: i64
  - status: enum { Active, Folded, AllIn }
  - position: u8 (seat number)
```

### 1.3 Table Manager
```
Table:
  - players: [8]?Player (up to 8 players)
  - community_cards: [5]Card (flop[3], turn, river)
  - dealer_position: u8
  - small_blind_pos: u8
  - big_blind_pos: u8
  - pot: PotManager
  - deck: Deck
  - current_street: Street
```

### 1.4 Pot Manager
```
PotManager:
  - main_pot: i64
  - side_pots: []SidePot
  - contributions: map[player_id -> amount]
  - calculateWinnings(): Distribute pots to winners
```

### 1.5 State Manager
```
GameState:
  - street: enum { PreFlop, Flop, Turn, River, Showdown }
  - action_to: u8 (player position)
  - min_raise: i64
  - last_aggressor: ?u8
  - betting_round_complete: bool
```

### 1.6 Hand Evaluator
```
Evaluator:
  - evaluate7Card(cards: [7]Card) -> u32 (hand rank)
  - getBest5Cards(cards: [7]Card) -> [5]Card
  - compareHands(hand1: [7]Card, hand2: [7]Card) -> Winner
```

## 2. LUT (Lookup Table) Structure

The LUT maps card combinations to cluster IDs for hand abstraction:

### 2.1 Data Structure
```python
# Python LUT structure
LUT = {
    'river': {
        (card1, card2, ..., card7): cluster_id,  # 7 cards -> cluster
        ...
    },
    'turn': {
        (card1, card2, ..., card6): cluster_id,  # 6 cards -> cluster
        ...
    },
    'flop': {
        (card1, card2, ..., card5): cluster_id,  # 5 cards -> cluster
        ...
    },
    'preflop': {
        (card1, card2): cluster_id,  # 2 cards -> cluster
        ...
    }
}
```

### 2.2 What Each Stage Represents
- **River**: Complete information (2 hole + 5 community) → direct hand strength cluster
- **Turn**: 2 hole + 4 community → cluster based on river possibilities
- **Flop**: 2 hole + 3 community → cluster based on turn/river possibilities  
- **Preflop**: 2 hole cards only → cluster based on starting hand strength

### 2.3 Cluster Assignment Process
1. Compute feature vector for each combination:
   - River: EHS (single value)
   - Turn: EHS distribution over possible rivers
   - Flop: EHS distribution over possible turns
   
2. Use K-means clustering to group similar feature vectors

3. Store mapping: combination → cluster_id

## 3. Clustering System Components

### 3.1 Equity Calculator
```
EquityCalculator:
  - calculateEHS(our_cards: [2]Card, board: []Card, n_simulations: u32) -> f32
    // EHS = P(win) + 0.5 * P(tie)
    // Uses Monte Carlo simulation against random opponent hands
```

### 3.2 Feature Extraction
```
River Features:
  - Input: 2 hole + 5 community cards
  - Output: EHS value (0.0 - 1.0)

Turn Features:
  - Input: 2 hole + 4 community cards  
  - Output: [n_river_clusters]f32 distribution
  - For each possible river card:
    - Calculate EHS
    - Map to river cluster
    - Accumulate probability

Flop Features:
  - Input: 2 hole + 3 community cards
  - Output: [n_turn_clusters]f32 distribution
  - For each possible turn card:
    - Calculate turn distribution
    - Map to turn cluster
    - Accumulate probability
```

### 3.3 K-Means Clustering
```
KMeans:
  - n_clusters: usize
  - centroids: [][f32]  // centroids[cluster_id] = feature_vector
  - fit(data: [][f32]): Train on feature vectors
  - predict(vector: [f32]) -> cluster_id
```

### 3.4 LUT Builder
```
LUTBuilder:
  - buildRiverLUT():
    1. Generate all river combinations
    2. Calculate EHS for each
    3. Cluster by EHS value
    4. Store: combo → cluster_id
    
  - buildTurnLUT():
    1. Generate all turn combinations
    2. For each, calculate distribution over river clusters
    3. Cluster by distribution vector
    4. Store: combo → cluster_id
    
  - buildFlopLUT():
    1. Generate all flop combinations
    2. For each, calculate distribution over turn clusters
    3. Cluster by distribution vector
    4. Store: combo → cluster_id
```

## 4. Key Algorithms

### 4.1 EHS Calculation
```zig
fn calculateEHS(our_cards: [2]Card, board: []Card, all_cards: []Card) f32 {
    wins = 0
    total = 0
    
    for (n_simulations) {
        // Sample opponent hand
        opp_cards = sampleOpponentHand(all_cards, our_cards, board)
        
        // Evaluate both hands
        our_rank = evaluator.evaluate7Card(our_cards ++ board)
        opp_rank = evaluator.evaluate7Card(opp_cards ++ board)
        
        // Count result
        if (our_rank < opp_rank) wins += 1.0
        else if (our_rank == opp_rank) wins += 0.5
        total += 1
    }
    
    return wins / total
}
```

### 4.2 River Distribution (for Turn)
```zig
fn calculateRiverDistribution(turn_combo: [6]Card) [n_river_clusters]f32 {
    distribution = [0.0; n_river_clusters]
    
    for (each possible river card) {
        river_combo = turn_combo ++ river_card
        ehs = calculateEHS(river_combo[0:2], river_combo[2:7])
        river_cluster = river_lut[river_combo]
        distribution[river_cluster] += 1.0 / n_possible_rivers
    }
    
    return distribution
}
```

## 5. Data Flow

```
1. Card Generation
   ↓
2. Combination Generation (river/turn/flop)
   ↓
3. Feature Extraction (EHS or distribution)
   ↓
4. K-Means Clustering
   ↓
5. LUT Storage (combo → cluster_id)
   ↓
6. Database Persistence
```

## 6. Memory Optimization

- **Streaming Processing**: Process combinations in batches
- **Chunked Storage**: Write to database every N items
- **Incremental K-Means**: Use MiniBatchKMeans for large datasets
- **Garbage Collection**: Explicit memory cleanup between batches

## 7. Database Schema

```sql
-- River data
CREATE TABLE river_data (
    combo_id INTEGER PRIMARY KEY,
    combo_cards BLOB,      -- Serialized [7]Card
    ehs REAL,              -- Expected hand strength
    cluster_id INTEGER     -- Assigned cluster
);

-- Turn data  
CREATE TABLE turn_data (
    combo_id INTEGER PRIMARY KEY,
    combo_cards BLOB,      -- Serialized [6]Card
    distribution BLOB,     -- Serialized [n_river_clusters]f32
    cluster_id INTEGER     -- Assigned cluster
);

-- Flop data
CREATE TABLE flop_data (
    combo_id INTEGER PRIMARY KEY,
    combo_cards BLOB,      -- Serialized [5]Card
    distribution BLOB,     -- Serialized [n_turn_clusters]f32
    cluster_id INTEGER     -- Assigned cluster
);
```

## 8. Implementation Priority

1. **Phase 1**: Core Components
   - Card, Deck, Hand Evaluator
   - Proper poker hand ranking

2. **Phase 2**: Equity Calculator
   - EHS calculation with Monte Carlo
   - Opponent hand sampling

3. **Phase 3**: Clustering System
   - K-Means implementation
   - Feature extraction for each stage

4. **Phase 4**: LUT Builder
   - River LUT (simplest)
   - Turn LUT (depends on river)
   - Flop LUT (depends on turn)

5. **Phase 5**: Integration & Testing
   - Verify against Python implementation
   - Performance optimization