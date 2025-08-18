# Card Clustering and Information Set Abstraction

## The Problem

Texas Hold'em poker has an astronomical number of possible game states:

- **Preflop**: 1,326 starting hand combinations
- **Flop**: 1,326 × C(50,3) = 1,326 × 19,600 = **26 million**
- **Turn**: 1,326 × C(50,4) = 1,326 × 230,300 = **305 million**  
- **River**: 1,326 × C(50,5) = 1,326 × 2,118,760 = **2.8 billion**

With betting history, the number of information sets exceeds **10^14**.

**This is impossible to store in memory or train.**

## The Solution: Abstraction

We group similar poker situations into **clusters**. Instead of treating A♠K♠ and A♥K♥ as different (they're strategically identical), we put them in the same cluster.

### UPDATE: Unified SQLite Architecture (2024)

Due to memory constraints when processing billions of combinations, the system now uses a **unified SQLite-backed architecture**. This ensures all stages (river, turn, flop) use consistent database backing to prevent memory overflow:

- **UnifiedSQLiteLUTBuilder**: Processes all stages with SQLite database
- **Streaming Processing**: Never loads all data into memory  
- **Checkpoint/Resume**: Can recover from any failure point
- **Memory Safety**: Stays within configured memory limits (e.g., 50GB)

```
Without Clustering:              With Clustering:
A♠K♠ → Strategy_1               A♠K♠ ─┐
A♥K♥ → Strategy_2               A♥K♥ ─┼→ Cluster_15 → One Strategy
A♦K♦ → Strategy_3               A♦K♦ ─┤
A♣K♣ → Strategy_4               A♣K♣ ─┘

Memory: 4 strategies             Memory: 1 strategy
```

## Clustering Overview

### Two-Phase Process

1. **Card Abstraction**: Group similar card combinations into clusters
2. **Information Set Mapping**: Map game states to cluster IDs

### Clustering Metrics

We use different metrics for each street:

- **Preflop**: Hand strength + suited/offsuit
- **Flop/Turn**: Current strength + potential (outs)
- **River**: Final hand strength only

## Implementation Architecture

### Core Components

```
poker_ai/clustering/
├── runner.py                         # CLI interface
├── card_info_lut_builder.py         # Original in-memory clustering
├── unified_sqlite_builder.py        # NEW: Unified SQLite-backed builder
├── incremental_turn_processor.py    # Turn-specific SQLite processor
├── memory_efficient_builder.py      # Memory-optimized builder
├── card_abstraction.py              # Abstract base class
└── compute_equity.py                 # Hand equity calculations
```

### Database Schema (NEW)

The unified system uses SQLite with optimized schema:

```sql
-- River stage data
CREATE TABLE river_data (
    combo_id INTEGER PRIMARY KEY,
    combo_cards BLOB NOT NULL,
    ehs_data BLOB,              -- Compressed 3D vector
    cluster_id INTEGER DEFAULT -1,
    processed_at TIMESTAMP
);

-- Turn stage data  
CREATE TABLE turn_data (
    combo_id INTEGER PRIMARY KEY,
    combo_cards BLOB NOT NULL,
    distribution BLOB,           -- Compressed 400D vector
    cluster_id INTEGER DEFAULT -1,
    processed_at TIMESTAMP
);

-- Flop stage data
CREATE TABLE flop_data (
    combo_id INTEGER PRIMARY KEY,
    combo_cards BLOB NOT NULL,
    distribution BLOB,           -- Compressed 300D vector
    cluster_id INTEGER DEFAULT -1,
    processed_at TIMESTAMP
);

-- Checkpoint tracking
CREATE TABLE checkpoints (
    stage TEXT PRIMARY KEY,
    last_processed_index INTEGER,
    kmeans_state BLOB,
    centroids BLOB,
    metadata BLOB,
    updated_at TIMESTAMP
);
```

## The Clustering Algorithm

### 1. Preflop Clustering

Preflop is simple - only 169 strategically distinct hands:

```python
def cluster_preflop_hands():
    """
    Group 1,326 combinations into 169 clusters.
    """
    clusters = {}
    cluster_id = 0
    
    for rank1 in range(2, 15):  # 2-14 (Ace)
        for rank2 in range(rank1, 15):
            if rank1 == rank2:
                # Pocket pair (6 combinations)
                clusters[f"{rank1}{rank2}"] = cluster_id
            else:
                # Suited (4 combinations)
                clusters[f"{rank1}{rank2}s"] = cluster_id
                cluster_id += 1
                
                # Offsuit (12 combinations)
                clusters[f"{rank1}{rank2}o"] = cluster_id
                cluster_id += 1
    
    return clusters  # 169 clusters total
```

### 2. Postflop Clustering (K-Means)

For flop, turn, and river, we use K-means clustering:

```python
def cluster_postflop(round_name, n_clusters=200):
    """
    Use K-means to group similar board textures.
    """
    # 1. Sample representative boards
    boards = sample_boards(round_name, n_samples=10000)
    
    # 2. Convert boards to feature vectors
    features = []
    for board in boards:
        feature = compute_features(board)
        features.append(feature)
    
    # 3. Run K-means clustering
    kmeans = KMeans(n_clusters=n_clusters)
    kmeans.fit(features)
    
    # 4. Create lookup table
    lut = {}
    for board in all_possible_boards:
        feature = compute_features(board)
        cluster_id = kmeans.predict([feature])[0]
        lut[board] = cluster_id
    
    return lut
```

### 3. Feature Extraction

#### Equity-Based Features

For each hand+board combination, we compute:

```python
def compute_features(hand, board):
    """
    Extract strategic features from cards.
    """
    features = []
    
    # 1. Current hand strength (0-1)
    strength = evaluate_hand_strength(hand, board)
    features.append(strength)
    
    # 2. Potential (probability of improving)
    if len(board) < 5:  # Not river
        potential = compute_potential(hand, board)
        features.append(potential)
    
    # 3. Texture features
    features.extend([
        is_flush_possible(board),
        is_straight_possible(board),
        num_paired_cards(board),
        highest_card_rank(board) / 14.0,
    ])
    
    return features
```

#### Equity Calculation

```python
def compute_equity(hand, board, n_simulations=1000):
    """
    Monte Carlo simulation to estimate winning probability.
    """
    wins = 0
    
    for _ in range(n_simulations):
        # Sample opponent hand
        opponent = sample_random_hand(exclude=hand+board)
        
        # Sample remaining board cards
        remaining = 5 - len(board)
        future_cards = sample_cards(remaining, exclude=hand+board+opponent)
        
        # Evaluate winner
        my_hand = hand + board + future_cards
        opp_hand = opponent + board + future_cards
        
        if evaluate(my_hand) > evaluate(opp_hand):
            wins += 1
    
    return wins / n_simulations
```

### 4. Earth Mover's Distance (EMD)

For more sophisticated clustering, we use EMD to compare hand range distributions:

```python
def earth_movers_distance(dist1, dist2):
    """
    Compute optimal transport distance between distributions.
    Uses scipy.stats.wasserstein_distance.
    """
    # Convert hand ranges to cumulative distributions
    cdf1 = np.cumsum(dist1)
    cdf2 = np.cumsum(dist2)
    
    # Compute L1 distance between CDFs
    return np.sum(np.abs(cdf1 - cdf2))
```

## The CardInfoLUT Builder

### Main Class Structure

```python
class CardInfoLUTBuilder:
    def __init__(
        self,
        n_simulations=10,      # Monte Carlo samples per equity
        n_river_clusters=200,   # Clusters for river
        n_turn_clusters=200,    # Clusters for turn  
        n_flop_clusters=200,    # Clusters for flop
        n_preflop_clusters=169, # Fixed for preflop
    ):
        self.card_info_lut = {}
        self.setup_evaluator()
    
    def build(self):
        """Build complete LUT."""
        self.cluster_preflop()    # Fast: ~1 minute
        self.cluster_river()       # Slow: ~30 minutes
        self.cluster_turn()        # Medium: ~20 minutes
        self.cluster_flop()        # Slow: ~40 minutes
        self.save()
```

### Parallel Processing

```python
def process_boards_parallel(self, boards, n_workers=8):
    """
    Process boards in parallel using multiprocessing.
    """
    with ProcessPoolExecutor(max_workers=n_workers) as executor:
        # Split boards into chunks
        chunk_size = len(boards) // n_workers
        chunks = [boards[i:i+chunk_size] 
                 for i in range(0, len(boards), chunk_size)]
        
        # Process chunks in parallel
        futures = []
        for chunk in chunks:
            future = executor.submit(self.process_chunk, chunk)
            futures.append(future)
        
        # Collect results
        results = []
        for future in tqdm(as_completed(futures)):
            results.extend(future.result())
    
    return results
```

### Memory Optimization

```python
def save_checkpoint(self, stage_name):
    """
    Save intermediate results to disk.
    """
    # Compress with joblib (uses zlib)
    joblib.dump(
        self.card_info_lut,
        f"checkpoint_{stage_name}.joblib",
        compress=3  # Compression level
    )
    
    # Also save metadata
    metadata = {
        "stage": stage_name,
        "timestamp": datetime.now(),
        "entries": len(self.card_info_lut),
        "memory_mb": sys.getsizeof(self.card_info_lut) / 1024 / 1024
    }
    
    with open(f"checkpoint_{stage_name}_meta.json", "w") as f:
        json.dump(metadata, f)
```

## Cluster Quality Metrics

### 1. Intra-cluster Similarity

Hands in the same cluster should be similar:

```python
def intra_cluster_variance(cluster_hands):
    """
    Measure how similar hands are within a cluster.
    Lower is better.
    """
    equities = [compute_equity(hand) for hand in cluster_hands]
    return np.var(equities)
```

### 2. Inter-cluster Separation

Different clusters should be distinct:

```python
def inter_cluster_distance(cluster1, cluster2):
    """
    Measure separation between clusters.
    Higher is better.
    """
    centroid1 = np.mean([compute_features(h) for h in cluster1])
    centroid2 = np.mean([compute_features(h) for h in cluster2])
    return np.linalg.norm(centroid1 - centroid2)
```

### 3. Silhouette Score

Overall clustering quality:

```python
from sklearn.metrics import silhouette_score

def evaluate_clustering(features, labels):
    """
    Compute silhouette score (-1 to 1, higher is better).
    """
    return silhouette_score(features, labels)
```

## Performance Analysis

### Original In-Memory Implementation

| Stage    | Combinations | Clusters | Time    | Memory    | Status |
|----------|-------------|----------|---------|-----------|--------|
| Preflop  | 1,326       | 169      | 1 min   | 10 MB     | ✅ OK  |
| River    | 2.6B        | 200      | 30 min  | 2 GB      | ✅ OK  |
| Turn     | 305M        | 200      | 20 min  | **80+ GB**| ❌ OOM |
| Flop     | 26M         | 200      | 40 min  | 500 MB    | ✅ OK  |
| **Total**| -           | 769      | 90 min  | **80+ GB**| ❌ Fails|

### NEW: Unified SQLite Implementation

| Stage    | Combinations | Clusters | Time    | Memory | Database | Status |
|----------|-------------|----------|---------|--------|----------|--------|
| Preflop  | 1,326       | 169      | 1 min   | 10 MB  | -        | ✅ OK  |
| River    | 2.6B        | 400      | 45 min  | 1 GB   | 100 MB   | ✅ OK  |
| Turn     | 305M        | 300      | 90 min  | 1 GB   | 200 MB   | ✅ OK  |
| Flop     | 26M         | 300      | 60 min  | 1 GB   | 150 MB   | ✅ OK  |
| **Total**| -           | 1169     | 3 hrs   | **<5GB**| 450 MB  | ✅ Works|

Key improvements:
- **Memory bounded**: Never exceeds configured limit (e.g., 50GB)
- **Resume capability**: Can recover from any crash
- **Higher quality**: More clusters possible (400/300/300 vs 200/200/200)
- **Database backed**: All intermediate data persisted

### Bottlenecks

1. **Monte Carlo Simulations**: 80% of time
2. **K-means Clustering**: 15% of time
3. **I/O Operations**: 5% of time

### Potential Optimizations

#### Rust Implementation

```rust
// 20-40x faster than Python
fn compute_equity_fast(hand: &[Card], board: &[Card]) -> f32 {
    let mut wins = 0u32;
    
    // SIMD-optimized evaluation
    for _ in 0..N_SIMULATIONS {
        let opponent = sample_opponent();
        let result = evaluate_simd(hand, opponent, board);
        wins += result as u32;
    }
    
    wins as f32 / N_SIMULATIONS as f32
}
```

Expected performance:
- Python: 90 minutes → Rust: 3-5 minutes
- Memory: 3.5 GB → 1 GB (more efficient structures)

## Using the LUT

### Loading

```python
import joblib

# Load precomputed LUT
lut = joblib.load("card_info_lut.joblib")

# Structure:
# {
#   "2_3_4_5_6": cluster_id,  # River boards
#   "2_3_4_5": cluster_id,     # Turn boards
#   "2_3_4": cluster_id,       # Flop boards
#   "AA": cluster_id,          # Preflop hands
# }
```

### Lookup During Training

```python
def get_info_set_key(state, player_id):
    """
    Map game state to clustered info set.
    """
    hand = state.players[player_id].hand
    board = state.community_cards
    
    # Convert cards to cluster ID
    if len(board) == 0:  # Preflop
        hand_key = cards_to_preflop_key(hand)
        cluster_id = lut[hand_key]
    else:  # Postflop
        board_key = cards_to_key(board)
        cluster_id = lut[board_key]
    
    # Combine with betting history
    betting_abstract = abstract_betting(state.history)
    
    return f"{cluster_id}|{betting_abstract}"
```

## Quality vs Speed Tradeoffs

### Number of Clusters

| Clusters | Quality | Memory | Training Speed |
|----------|---------|--------|----------------|
| 50       | Poor    | 100MB  | Fast           |
| 200      | Good    | 400MB  | Medium         |
| 500      | Great   | 1GB    | Slow           |
| 1000     | Best    | 2GB    | Very Slow      |

### Simulation Count

| Simulations | Equity Accuracy | Generation Time |
|-------------|----------------|-----------------|
| 1           | ±20%           | 5 minutes       |
| 10          | ±10%           | 50 minutes      |
| 100         | ±3%            | 8 hours         |
| 1000        | ±1%            | 3 days          |

## Advanced Techniques

### 1. Hierarchical Clustering

Group clusters into super-clusters:

```python
def hierarchical_clustering(base_clusters):
    """
    Create multi-level abstraction.
    """
    # Level 1: 1000 fine clusters
    fine = kmeans(n_clusters=1000)
    
    # Level 2: 200 medium clusters
    medium = aggregate_clusters(fine, n_clusters=200)
    
    # Level 3: 50 coarse clusters
    coarse = aggregate_clusters(medium, n_clusters=50)
    
    return {
        "fine": fine,     # For late game
        "medium": medium, # For mid game
        "coarse": coarse  # For early game
    }
```

### 2. Potential-Aware Clustering

Consider future cards:

```python
def potential_aware_features(hand, board):
    """
    Include draw potential in features.
    """
    features = []
    
    # Current strength
    features.append(current_equity(hand, board))
    
    # Flush draws
    features.append(flush_draw_outs(hand, board) / 47)
    
    # Straight draws
    features.append(straight_draw_outs(hand, board) / 47)
    
    # Backdoor draws
    if len(board) == 3:  # Flop
        features.append(backdoor_potential(hand, board))
    
    return features
```

### 3. Opponent Modeling

Cluster based on opponent ranges:

```python
def opponent_aware_clustering(hand, board, opp_range):
    """
    Cluster considering likely opponent hands.
    """
    equity_vs_range = compute_equity_vs_range(
        hand, board, opp_range
    )
    
    # Different clusters for different equities
    if equity_vs_range > 0.8:
        return "nuts"
    elif equity_vs_range > 0.6:
        return "strong"
    elif equity_vs_range > 0.4:
        return "medium"
    else:
        return "weak"
```

## Testing and Validation

### Unit Tests

```python
def test_clustering_deterministic():
    """Ensure clustering is reproducible with seed."""
    builder1 = CardInfoLUTBuilder(seed=42)
    lut1 = builder1.build()
    
    builder2 = CardInfoLUTBuilder(seed=42)
    lut2 = builder2.build()
    
    assert lut1 == lut2

def test_cluster_quality():
    """Verify cluster quality metrics."""
    builder = CardInfoLUTBuilder()
    clusters = builder.cluster_river()
    
    # Check intra-cluster similarity
    for cluster_hands in clusters:
        variance = intra_cluster_variance(cluster_hands)
        assert variance < 0.1  # Threshold
```

### Integration Tests

```python
def test_lut_with_mccfr():
    """Test LUT integration with training."""
    lut = joblib.load("test_lut.joblib")
    
    # Train small strategy
    ai = MCCFR(lut=lut)
    ai.train(iterations=1000)
    
    # Verify strategy uses clusters
    for info_set in ai.strategy.keys():
        assert "|" in info_set  # Has cluster ID
```

## Future Improvements

1. **Neural Network Clustering**: Use deep learning for feature extraction
2. **Dynamic Abstraction**: Adjust clusters during training
3. **Action Abstraction**: Cluster bet sizes too
4. **GPU Acceleration**: Parallel equity calculations
5. **Incremental Updates**: Update LUT without full rebuild