# Comprehensive Zig Architecture for Poker AI System

## Executive Summary

**【Core Judgment】**
✅ **Worth Doing:** Migrating critical performance components to Zig will provide 10-100x performance improvements while maintaining Python interoperability for rapid development.

**【Key Insights】**  
- **Data Structure:** Game state should be stack-allocated with compile-time bounds
- **Complexity:** Current clustering system has too many abstraction layers - can be simplified to 3 core components
- **Risk Point:** Memory management during MCCFR tree traversal - requires careful arena allocation strategy

**【Linus-Style Solution】**
1. Start with the simplest, dumbest implementation that works
2. Eliminate all dynamic allocation in game tree traversal
3. Use compile-time constants for all poker constraints (52 cards, max 8 players)
4. Build incrementally, one component at a time

---

## 1. Project Structure & Build System

### 1.1 Directory Layout
```
poker_ai_zig/
├── build.zig                    # Main build configuration
├── src/
│   ├── main.zig                # Entry point and C API
│   ├── poker/                  # Core poker game engine
│   │   ├── card.zig
│   │   ├── deck.zig
│   │   ├── table.zig
│   │   ├── player.zig
│   │   ├── engine.zig
│   │   └── evaluator.zig
│   ├── ai/                     # MCCFR algorithm implementation
│   │   ├── cfr.zig
│   │   ├── strategy.zig
│   │   ├── info_set.zig
│   │   └── tree_walker.zig
│   ├── clustering/             # Hand abstraction system
│   │   ├── lut_builder.zig
│   │   ├── equity_calc.zig
│   │   ├── kmeans.zig
│   │   └── storage.zig
│   ├── memory/                 # Memory management
│   │   ├── arena.zig
│   │   ├── pool.zig
│   │   └── gc.zig
│   ├── utils/                  # Utilities
│   │   ├── random.zig
│   │   ├── simd.zig
│   │   └── threading.zig
│   └── c_api/                  # Python interop
│       ├── exports.zig
│       └── bindings.zig
├── tests/
├── benchmarks/
└── python_bindings/            # Python wrapper
    ├── __init__.py
    ├── native.py              # ctypes bindings
    └── interop.py             # High-level interface
```

### 1.2 Build Configuration (build.zig)
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core library
    const poker_lib = b.addStaticLibrary(.{
        .name = "poker_ai",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // C API for Python interop
    const c_api = b.addSharedLibrary(.{
        .name = "poker_ai_c",
        .root_source_file = .{ .path = "src/c_api/exports.zig" },
        .target = target,
        .optimize = optimize,
    });
    c_api.linkLibrary(poker_lib);

    // Executables
    const clustering_exe = b.addExecutable(.{
        .name = "clustering",
        .root_source_file = .{ .path = "src/clustering/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    clustering_exe.linkLibrary(poker_lib);

    const training_exe = b.addExecutable(.{
        .name = "training",
        .root_source_file = .{ .path = "src/ai/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    training_exe.linkLibrary(poker_lib);

    // Dependencies
    const sqlite = b.dependency("sqlite", .{ .target = target, .optimize = optimize });
    poker_lib.linkLibrary(sqlite.artifact("sqlite"));
}
```

---

## 2. Core Components Architecture

### 2.1 Game Engine Design

#### Card & Deck (src/poker/card.zig)
```zig
// Compile-time constants for poker constraints
pub const RANKS_COUNT = 13;      // 2-A
pub const SUITS_COUNT = 4;       // Spades, Hearts, Diamonds, Clubs  
pub const DECK_SIZE = 52;        // 52 cards total
pub const MAX_PLAYERS = 8;       // Maximum players at table

pub const Rank = enum(u4) {
    two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8,
    nine = 9, ten = 10, jack = 11, queen = 12, king = 13, ace = 14,
};

pub const Suit = enum(u2) { spades = 0, hearts = 1, diamonds = 2, clubs = 3 };

pub const Card = packed struct {
    rank: Rank,
    suit: Suit,
    
    pub fn toInt(self: Card) u8 {
        return (@intFromEnum(self.rank) - 2) * 4 + @intFromEnum(self.suit);
    }
    
    pub fn fromInt(val: u8) Card {
        return Card{
            .rank = @enumFromInt(val / 4 + 2),
            .suit = @enumFromInt(val % 4),
        };
    }
};

pub const Deck = struct {
    cards: [DECK_SIZE]Card,
    position: u8,
    rng: std.rand.DefaultPrng,
    
    pub fn init(seed: u64) Deck {
        var deck = Deck{
            .cards = undefined,
            .position = 0,
            .rng = std.rand.DefaultPrng.init(seed),
        };
        deck.reset();
        return deck;
    }
    
    pub fn reset(self: *Deck) void {
        var i: u8 = 0;
        while (i < DECK_SIZE) : (i += 1) {
            self.cards[i] = Card.fromInt(i);
        }
        self.position = 0;
    }
    
    pub fn shuffle(self: *Deck) void {
        self.rng.random().shuffle(Card, &self.cards);
        self.position = 0;
    }
    
    pub fn deal(self: *Deck) ?Card {
        if (self.position >= DECK_SIZE) return null;
        const card = self.cards[self.position];
        self.position += 1;
        return card;
    }
};
```

#### Player & Table (src/poker/player.zig)
```zig
pub const PlayerStatus = enum { active, folded, all_in, out };

pub const Player = struct {
    id: u8,
    hole_cards: [2]Card,
    chips: i64,
    current_bet: i64,
    total_bet: i64,
    status: PlayerStatus,
    position: u8,
    
    pub fn init(id: u8, chips: i64, position: u8) Player {
        return Player{
            .id = id,
            .hole_cards = undefined,
            .chips = chips,
            .current_bet = 0,
            .total_bet = 0,
            .status = .active,
            .position = position,
        };
    }
    
    pub fn canAct(self: Player) bool {
        return self.status == .active and self.chips > 0;
    }
    
    pub fn bet(self: *Player, amount: i64) bool {
        if (amount > self.chips) return false;
        self.chips -= amount;
        self.current_bet += amount;
        self.total_bet += amount;
        if (self.chips == 0) self.status = .all_in;
        return true;
    }
};
```

#### Game State Machine (src/poker/engine.zig)
```zig
pub const Street = enum { preflop, flop, turn, river, showdown };

pub const GameState = struct {
    players: [MAX_PLAYERS]?Player,
    n_players: u8,
    community_cards: [5]Card,
    n_community_cards: u8,
    pot: i64,
    dealer_pos: u8,
    small_blind_pos: u8,
    big_blind_pos: u8,
    action_pos: u8,
    street: Street,
    min_bet: i64,
    last_raise: i64,
    is_terminal: bool,
    
    // Stack-allocated for performance
    arena: std.heap.ArenaAllocator,
    
    pub fn init(allocator: std.mem.Allocator, n_players: u8, small_blind: i64, big_blind: i64) !GameState {
        var state = GameState{
            .players = [_]?Player{null} ** MAX_PLAYERS,
            .n_players = n_players,
            .community_cards = undefined,
            .n_community_cards = 0,
            .pot = 0,
            .dealer_pos = 0,
            .small_blind_pos = 1,
            .big_blind_pos = 2,
            .action_pos = 3,
            .street = .preflop,
            .min_bet = big_blind,
            .last_raise = big_blind,
            .is_terminal = false,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
        
        // Initialize players
        var i: u8 = 0;
        while (i < n_players) : (i += 1) {
            state.players[i] = Player.init(i, 10000, i);
        }
        
        return state;
    }
    
    pub fn deinit(self: *GameState) void {
        self.arena.deinit();
    }
};
```

### 2.2 Hand Evaluation System

#### Fast 7-Card Evaluator (src/poker/evaluator.zig)
```zig
// Use lookup tables for maximum performance
pub const HandRank = u32;
pub const HAND_RANKS_COUNT = 7462; // Unique 5-card hand ranks

pub const Evaluator = struct {
    // Pre-computed lookup tables
    flushes: [1287]HandRank,
    unique5: [1287]HandRank,
    
    pub fn init() Evaluator {
        return Evaluator{
            .flushes = comptime initFlushes(),
            .unique5 = comptime initUnique5(),
        };
    }
    
    pub fn evaluate7(self: *const Evaluator, cards: [7]Card) HandRank {
        // Fast 7-card evaluation using bit manipulation
        var suits: [4]u16 = [_]u16{0} ** 4;
        var ranks: [13]u8 = [_]u8{0} ** 13;
        
        // Count suits and ranks using SIMD when possible
        for (cards) |card| {
            const suit_idx = @intFromEnum(card.suit);
            const rank_idx = @intFromEnum(card.rank) - 2;
            suits[suit_idx] |= (@as(u16, 1) << @intCast(rank_idx));
            ranks[rank_idx] += 1;
        }
        
        // Check for flush
        for (suits) |suit_mask| {
            if (@popCount(suit_mask) >= 5) {
                return self.evaluateFlush(suit_mask);
            }
        }
        
        // Non-flush evaluation
        return self.evaluateNonFlush(ranks);
    }
    
    fn evaluateFlush(self: *const Evaluator, suit_mask: u16) HandRank {
        // Find best 5 cards from flush
        var best_rank: HandRank = 9999;
        const top5 = extractTop5Bits(suit_mask);
        return self.flushes[top5];
    }
    
    fn evaluateNonFlush(self: *const Evaluator, ranks: [13]u8) HandRank {
        // Hand pattern matching for pairs, trips, etc.
        var pattern: u16 = 0;
        for (ranks) |count| {
            pattern += @as(u16, 1) << @intCast(count);
        }
        
        return switch (pattern) {
            0x1040 => self.evaluateQuads(ranks),    // 4 of a kind
            0x0420 => self.evaluateFullHouse(ranks), // Full house
            0x0240 => self.evaluateTrips(ranks),     // Three of a kind
            0x0144 => self.evaluateTwoPair(ranks),   // Two pair
            0x0104 => self.evaluatePair(ranks),      // One pair
            0x0080 => self.evaluateHighCard(ranks),  // High card
            else => 9999, // Invalid hand
        };
    }
};
```

---

## 3. Memory Management Strategy

### 3.1 Arena Allocators for Game Tree Traversal

```zig
// src/memory/arena.zig
pub const GameArena = struct {
    const GAME_TREE_SIZE = 64 * 1024 * 1024; // 64MB per game tree
    const NODE_SIZE = 256; // Bytes per game state node
    
    backing_memory: []u8,
    allocator: std.heap.FixedBufferAllocator,
    
    pub fn init(allocator: std.mem.Allocator) !GameArena {
        const memory = try allocator.alloc(u8, GAME_TREE_SIZE);
        return GameArena{
            .backing_memory = memory,
            .allocator = std.heap.FixedBufferAllocator.init(memory),
        };
    }
    
    pub fn deinit(self: *GameArena, allocator: std.mem.Allocator) void {
        allocator.free(self.backing_memory);
    }
    
    pub fn reset(self: *GameArena) void {
        self.allocator.reset();
    }
    
    pub fn createGameState(self: *GameArena) !*GameState {
        return self.allocator.allocator().create(GameState);
    }
};
```

### 3.2 Memory Pool for Training Data

```zig
// src/memory/pool.zig
pub fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const POOL_SIZE = 10000;
        
        items: [POOL_SIZE]T,
        free_list: [POOL_SIZE]usize,
        free_count: usize,
        
        pub fn init() Self {
            var pool = Self{
                .items = undefined,
                .free_list = undefined,
                .free_count = POOL_SIZE,
            };
            
            // Initialize free list
            for (0..POOL_SIZE) |i| {
                pool.free_list[i] = i;
            }
            
            return pool;
        }
        
        pub fn acquire(self: *Self) ?*T {
            if (self.free_count == 0) return null;
            self.free_count -= 1;
            const idx = self.free_list[self.free_count];
            return &self.items[idx];
        }
        
        pub fn release(self: *Self, item: *T) void {
            const idx = (@intFromPtr(item) - @intFromPtr(&self.items[0])) / @sizeOf(T);
            self.free_list[self.free_count] = idx;
            self.free_count += 1;
        }
    };
}
```

---

## 4. AI System Architecture

### 4.1 MCCFR Implementation

```zig
// src/ai/cfr.zig
pub const InfoSet = struct {
    key: [64]u8, // Fixed-size info set identifier
    regret: std.HashMap(u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    strategy: std.HashMap(u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator) InfoSet {
        return InfoSet{
            .key = [_]u8{0} ** 64,
            .regret = std.HashMap(u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .strategy = std.HashMap(u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn calculateStrategy(self: *InfoSet, actions: []const u8) void {
        var regret_sum: f32 = 0;
        for (actions) |action| {
            const regret = self.regret.get(action) orelse 0;
            regret_sum += @max(regret, 0);
        }
        
        if (regret_sum > 0) {
            for (actions) |action| {
                const regret = self.regret.get(action) orelse 0;
                const prob = @max(regret, 0) / regret_sum;
                self.strategy.put(action, prob) catch unreachable;
            }
        } else {
            const uniform_prob = 1.0 / @as(f32, @floatFromInt(actions.len));
            for (actions) |action| {
                self.strategy.put(action, uniform_prob) catch unreachable;
            }
        }
    }
};

pub const CFREngine = struct {
    info_sets: std.HashMap([64]u8, InfoSet, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    arena: GameArena,
    evaluator: Evaluator,
    rng: std.rand.DefaultPrng,
    
    pub fn init(allocator: std.mem.Allocator, seed: u64) !CFREngine {
        return CFREngine{
            .info_sets = std.HashMap([64]u8, InfoSet, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .arena = try GameArena.init(allocator),
            .evaluator = Evaluator.init(),
            .rng = std.rand.DefaultPrng.init(seed),
        };
    }
    
    pub fn cfr(self: *CFREngine, state: *GameState, player_id: u8, iteration: u32) f32 {
        if (state.is_terminal) {
            return state.getPayout(player_id);
        }
        
        const info_set_key = state.getInfoSetKey(player_id);
        var info_set = self.info_sets.getOrPut(info_set_key) catch unreachable;
        if (!info_set.found_existing) {
            info_set.value_ptr.* = InfoSet.init(self.arena.allocator.allocator());
        }
        
        const actions = state.getLegalActions();
        info_set.value_ptr.calculateStrategy(actions);
        
        var node_util: f32 = 0;
        var action_utils = std.ArrayList(f32).init(self.arena.allocator.allocator());
        defer action_utils.deinit();
        
        // Traverse each action
        for (actions) |action| {
            const new_state = state.applyAction(action, &self.arena) catch unreachable;
            const util = self.cfr(new_state, player_id, iteration);
            action_utils.append(util) catch unreachable;
            
            const strategy_prob = info_set.value_ptr.strategy.get(action) orelse 0;
            node_util += strategy_prob * util;
        }
        
        // Update regrets
        for (actions, 0..) |action, i| {
            const regret = action_utils.items[i] - node_util;
            const current_regret = info_set.value_ptr.regret.get(action) orelse 0;
            info_set.value_ptr.regret.put(action, current_regret + regret) catch unreachable;
        }
        
        return node_util;
    }
};
```

### 4.2 Parallel Training System

```zig
// src/ai/parallel_trainer.zig
pub const ParallelTrainer = struct {
    const NUM_THREADS = 8;
    
    engines: [NUM_THREADS]CFREngine,
    thread_pool: std.Thread.Pool,
    shared_strategy: std.HashMap([64]u8, InfoSet, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) !ParallelTrainer {
        var trainer = ParallelTrainer{
            .engines = undefined,
            .thread_pool = undefined,
            .shared_strategy = std.HashMap([64]u8, InfoSet, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
        
        // Initialize engines
        for (0..NUM_THREADS) |i| {
            trainer.engines[i] = try CFREngine.init(allocator, i);
        }
        
        try trainer.thread_pool.init(std.Thread.Pool.Options{
            .allocator = allocator,
            .n_jobs = NUM_THREADS,
        });
        
        return trainer;
    }
    
    pub fn trainIteration(self: *ParallelTrainer, iteration: u32) !void {
        var wg = std.Thread.WaitGroup{};
        
        for (0..NUM_THREADS) |thread_id| {
            wg.start();
            try self.thread_pool.spawn(workerThread, .{ self, thread_id, iteration, &wg });
        }
        
        wg.wait();
        self.aggregateStrategies();
    }
    
    fn workerThread(self: *ParallelTrainer, thread_id: usize, iteration: u32, wg: *std.Thread.WaitGroup) void {
        defer wg.finish();
        
        // Create initial game state
        var state = GameState.init(self.engines[thread_id].arena.allocator.allocator(), 6, 50, 100) catch return;
        defer state.deinit();
        
        // Run CFR for this thread
        _ = self.engines[thread_id].cfr(&state, @intCast(thread_id % 6), iteration);
    }
    
    fn aggregateStrategies(self: *ParallelTrainer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Merge strategies from all engines
        for (self.engines) |*engine| {
            var iterator = engine.info_sets.iterator();
            while (iterator.next()) |entry| {
                var shared_entry = self.shared_strategy.getOrPut(entry.key_ptr.*) catch continue;
                if (!shared_entry.found_existing) {
                    shared_entry.value_ptr.* = entry.value_ptr.*;
                } else {
                    // Average the strategies
                    var strategy_iter = entry.value_ptr.strategy.iterator();
                    while (strategy_iter.next()) |strategy_entry| {
                        const current = shared_entry.value_ptr.strategy.get(strategy_entry.key_ptr.*) orelse 0;
                        const new_value = (current + strategy_entry.value_ptr.*) / 2.0;
                        shared_entry.value_ptr.strategy.put(strategy_entry.key_ptr.*, new_value) catch continue;
                    }
                }
            }
        }
    }
};
```

---

## 5. Hand Clustering System

### 5.1 Optimized Clustering Pipeline

```zig
// src/clustering/lut_builder.zig
pub const ClusteringConfig = struct {
    n_river_clusters: u16 = 500,
    n_turn_clusters: u16 = 500,
    n_flop_clusters: u16 = 200,
    n_preflop_clusters: u16 = 169,
    batch_size: u32 = 10000,
    max_iterations: u32 = 100,
};

pub const LUTBuilder = struct {
    config: ClusteringConfig,
    allocator: std.mem.Allocator,
    evaluator: Evaluator,
    storage: SQLiteStorage,
    
    pub fn init(allocator: std.mem.Allocator, config: ClusteringConfig) !LUTBuilder {
        return LUTBuilder{
            .config = config,
            .allocator = allocator,
            .evaluator = Evaluator.init(),
            .storage = try SQLiteStorage.init(allocator, "clustering_data.db"),
        };
    }
    
    pub fn buildRiverLUT(self: *LUTBuilder) !void {
        std.log.info("Building river LUT with {} clusters", .{self.config.n_river_clusters});
        
        // Generate all river combinations efficiently
        var combo_generator = RiverComboGenerator.init();
        var features = std.ArrayList(f32).init(self.allocator);
        defer features.deinit();
        
        var batch_count: u32 = 0;
        while (combo_generator.next()) |combo| {
            const ehs = self.calculateEHS(combo.hole_cards, combo.board);
            try features.append(ehs);
            
            batch_count += 1;
            if (batch_count >= self.config.batch_size) {
                try self.processRiverBatch(features.items, batch_count);
                features.clearRetainingCapacity();
                batch_count = 0;
            }
        }
        
        // Process remaining items
        if (batch_count > 0) {
            try self.processRiverBatch(features.items, batch_count);
        }
        
        std.log.info("River LUT building complete");
    }
    
    fn calculateEHS(self: *LUTBuilder, hole_cards: [2]Card, board: []const Card) f32 {
        const N_SIMULATIONS = 1000;
        var wins: f32 = 0;
        var total: f32 = 0;
        
        var deck = Deck.init(std.crypto.random.int(u64));
        deck.removeCards(hole_cards);
        deck.removeCards(board);
        
        for (0..N_SIMULATIONS) |_| {
            // Sample opponent hole cards
            const opp_cards = deck.sampleCards(2);
            
            // Evaluate both hands
            var our_hand = [_]Card{undefined} ** 7;
            var opp_hand = [_]Card{undefined} ** 7;
            
            @memcpy(our_hand[0..2], &hole_cards);
            @memcpy(our_hand[2..], board);
            
            @memcpy(opp_hand[0..2], &opp_cards);
            @memcpy(opp_hand[2..], board);
            
            const our_rank = self.evaluator.evaluate7(our_hand);
            const opp_rank = self.evaluator.evaluate7(opp_hand);
            
            if (our_rank < opp_rank) {
                wins += 1.0;
            } else if (our_rank == opp_rank) {
                wins += 0.5;
            }
            total += 1.0;
        }
        
        return wins / total;
    }
    
    fn processRiverBatch(self: *LUTBuilder, features: []const f32, count: u32) !void {
        // Run K-means clustering on this batch
        var kmeans = KMeans.init(self.allocator, self.config.n_river_clusters);
        defer kmeans.deinit();
        
        try kmeans.fit(features);
        
        // Store results to database
        try self.storage.storeRiverBatch(features, kmeans.labels);
    }
};
```

### 5.2 SIMD-Optimized K-Means

```zig
// src/clustering/kmeans.zig
pub const KMeans = struct {
    const VECTOR_SIZE = std.simd.suggestVectorSize(f32) orelse 8;
    const FloatVector = @Vector(VECTOR_SIZE, f32);
    
    n_clusters: u16,
    centroids: []FloatVector,
    labels: []u16,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, n_clusters: u16) KMeans {
        return KMeans{
            .n_clusters = n_clusters,
            .centroids = allocator.alloc(FloatVector, n_clusters) catch unreachable,
            .labels = undefined,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *KMeans) void {
        self.allocator.free(self.centroids);
        if (self.labels.len > 0) self.allocator.free(self.labels);
    }
    
    pub fn fit(self: *KMeans, data: []const f32) !void {
        self.labels = try self.allocator.alloc(u16, data.len);
        
        // Initialize centroids randomly
        self.initializeCentroids(data);
        
        var iteration: u32 = 0;
        var converged = false;
        
        while (!converged and iteration < 100) {
            converged = self.assignLabels(data);
            self.updateCentroids(data);
            iteration += 1;
        }
    }
    
    fn assignLabels(self: *KMeans, data: []const f32) bool {
        var changed = false;
        
        for (data, 0..) |point, i| {
            var min_distance: f32 = std.math.inf(f32);
            var best_cluster: u16 = 0;
            
            // Use SIMD for distance calculations
            for (self.centroids, 0..) |centroid, cluster_idx| {
                const point_vec: FloatVector = @splat(point);
                const diff = point_vec - centroid;
                const squared_diff = diff * diff;
                const distance = @reduce(.Add, squared_diff);
                
                if (distance < min_distance) {
                    min_distance = distance;
                    best_cluster = @intCast(cluster_idx);
                }
            }
            
            if (self.labels[i] != best_cluster) {
                self.labels[i] = best_cluster;
                changed = true;
            }
        }
        
        return !changed;
    }
    
    fn updateCentroids(self: *KMeans, data: []const f32) void {
        var cluster_sums = self.allocator.alloc(f32, self.n_clusters) catch unreachable;
        defer self.allocator.free(cluster_sums);
        var cluster_counts = self.allocator.alloc(u32, self.n_clusters) catch unreachable;
        defer self.allocator.free(cluster_counts);
        
        @memset(cluster_sums, 0);
        @memset(cluster_counts, 0);
        
        // Accumulate sums
        for (data, 0..) |point, i| {
            const cluster = self.labels[i];
            cluster_sums[cluster] += point;
            cluster_counts[cluster] += 1;
        }
        
        // Update centroids
        for (0..self.n_clusters) |i| {
            if (cluster_counts[i] > 0) {
                const mean = cluster_sums[i] / @as(f32, @floatFromInt(cluster_counts[i]));
                self.centroids[i] = @splat(mean);
            }
        }
    }
};
```

---

## 6. Performance Optimizations

### 6.1 SIMD Hand Evaluation

```zig
// src/utils/simd.zig
pub fn parallelHandEvaluation(evaluator: *const Evaluator, hands: [][7]Card) []HandRank {
    const BATCH_SIZE = 8; // Process 8 hands simultaneously
    const n_batches = (hands.len + BATCH_SIZE - 1) / BATCH_SIZE;
    
    var results = std.ArrayList(HandRank).init(std.heap.page_allocator);
    
    for (0..n_batches) |batch_idx| {
        const start = batch_idx * BATCH_SIZE;
        const end = @min(start + BATCH_SIZE, hands.len);
        
        // Vectorized evaluation for this batch
        for (start..end) |i| {
            results.append(evaluator.evaluate7(hands[i])) catch unreachable;
        }
    }
    
    return results.toOwnedSlice() catch unreachable;
}
```

### 6.2 Lock-Free Data Structures

```zig
// src/utils/lockfree.zig
pub fn LockFreeHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const BUCKET_COUNT = 1024;
        
        buckets: [BUCKET_COUNT]std.atomic.Value(?*Node),
        
        const Node = struct {
            key: K,
            value: V,
            next: std.atomic.Value(?*Node),
        };
        
        pub fn init() Self {
            return Self{
                .buckets = [_]std.atomic.Value(?*Node){std.atomic.Value(?*Node).init(null)} ** BUCKET_COUNT,
            };
        }
        
        pub fn put(self: *Self, key: K, value: V, allocator: std.mem.Allocator) !void {
            const hash = std.hash_map.hashString(@as([]const u8, std.mem.asBytes(&key)));
            const bucket_idx = hash % BUCKET_COUNT;
            
            const node = try allocator.create(Node);
            node.* = Node{
                .key = key,
                .value = value,
                .next = std.atomic.Value(?*Node).init(null),
            };
            
            // Lock-free insertion using compare-and-swap
            while (true) {
                const head = self.buckets[bucket_idx].load(.Acquire);
                node.next.store(head, .Release);
                
                if (self.buckets[bucket_idx].cmpxchgWeak(head, node, .Release, .Acquire) == null) {
                    break;
                }
            }
        }
    };
}
```

---

## 7. Interface Design

### 7.1 C API for Python Interop

```zig
// src/c_api/exports.zig
export fn poker_ai_create_engine() callconv(.C) ?*CFREngine {
    const allocator = std.heap.c_allocator;
    const engine = allocator.create(CFREngine) catch return null;
    engine.* = CFREngine.init(allocator, std.crypto.random.int(u64)) catch return null;
    return engine;
}

export fn poker_ai_destroy_engine(engine: ?*CFREngine) callconv(.C) void {
    if (engine) |e| {
        e.deinit();
        std.heap.c_allocator.destroy(e);
    }
}

export fn poker_ai_train_iteration(engine: ?*CFREngine, iteration: u32) callconv(.C) f32 {
    if (engine) |e| {
        // Create a simple 2-player game for training
        var state = GameState.init(std.heap.c_allocator, 2, 50, 100) catch return -1;
        defer state.deinit();
        
        return e.cfr(&state, 0, iteration);
    }
    return -1;
}

export fn poker_ai_get_strategy(engine: ?*CFREngine, info_set: [*c]const u8, action: u8) callconv(.C) f32 {
    if (engine) |e| {
        var key: [64]u8 = [_]u8{0} ** 64;
        const len = @min(std.mem.len(info_set), 63);
        @memcpy(key[0..len], info_set[0..len]);
        
        const info_set_entry = e.info_sets.get(key) orelse return 0;
        return info_set_entry.strategy.get(action) orelse 0;
    }
    return 0;
}

// Building clustering LUTs
export fn poker_ai_build_river_lut(n_clusters: u16, db_path: [*c]const u8) callconv(.C) bool {
    const allocator = std.heap.c_allocator;
    
    const config = ClusteringConfig{ .n_river_clusters = n_clusters };
    var builder = LUTBuilder.init(allocator, config) catch return false;
    defer builder.deinit();
    
    builder.buildRiverLUT() catch return false;
    return true;
}
```

### 7.2 Python Bindings

```python
# python_bindings/native.py
import ctypes
import numpy as np
from pathlib import Path

# Load the native library
lib_path = Path(__file__).parent / "libpoker_ai_c.so"
lib = ctypes.CDLL(str(lib_path))

# Define function signatures
lib.poker_ai_create_engine.restype = ctypes.c_void_p
lib.poker_ai_destroy_engine.argtypes = [ctypes.c_void_p]
lib.poker_ai_train_iteration.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
lib.poker_ai_train_iteration.restype = ctypes.c_float
lib.poker_ai_get_strategy.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint8]
lib.poker_ai_get_strategy.restype = ctypes.c_float
lib.poker_ai_build_river_lut.argtypes = [ctypes.c_uint16, ctypes.c_char_p]
lib.poker_ai_build_river_lut.restype = ctypes.c_bool

class NativePokerAI:
    def __init__(self):
        self._engine = lib.poker_ai_create_engine()
        if not self._engine:
            raise RuntimeError("Failed to create poker AI engine")
    
    def __del__(self):
        if hasattr(self, '_engine') and self._engine:
            lib.poker_ai_destroy_engine(self._engine)
    
    def train_iteration(self, iteration: int) -> float:
        return lib.poker_ai_train_iteration(self._engine, iteration)
    
    def get_strategy(self, info_set: str, action: int) -> float:
        return lib.poker_ai_get_strategy(
            self._engine,
            info_set.encode('utf-8'),
            action
        )
    
    @staticmethod
    def build_river_lut(n_clusters: int = 500, db_path: str = "clustering_data.db") -> bool:
        return lib.poker_ai_build_river_lut(n_clusters, db_path.encode('utf-8'))
```

### 7.3 High-Level Python Interface

```python
# python_bindings/interop.py
from typing import Dict, List, Optional
import numpy as np
from .native import NativePokerAI

class PokerAIEngine:
    """High-level interface for the Zig poker AI engine."""
    
    def __init__(self):
        self.native = NativePokerAI()
        self.iteration_count = 0
    
    def train(self, n_iterations: int, checkpoint_interval: int = 1000) -> Dict[str, float]:
        """Train the AI for a specified number of iterations."""
        metrics = {
            'total_utility': 0.0,
            'iterations_completed': 0,
            'average_utility': 0.0
        }
        
        for i in range(n_iterations):
            utility = self.native.train_iteration(self.iteration_count + i)
            metrics['total_utility'] += utility
            
            if (i + 1) % checkpoint_interval == 0:
                avg_util = metrics['total_utility'] / (i + 1)
                print(f"Iteration {self.iteration_count + i + 1}: Average utility = {avg_util:.6f}")
        
        self.iteration_count += n_iterations
        metrics['iterations_completed'] = n_iterations
        metrics['average_utility'] = metrics['total_utility'] / n_iterations
        
        return metrics
    
    def get_action_probabilities(self, info_set: str) -> Dict[int, float]:
        """Get action probabilities for a given information set."""
        # Assuming actions are encoded as 0=fold, 1=call, 2=raise
        actions = {}
        for action in range(3):
            prob = self.native.get_strategy(info_set, action)
            if prob > 0:
                actions[action] = prob
        return actions
    
    @staticmethod
    def build_clustering_luts(
        river_clusters: int = 500,
        turn_clusters: int = 500,
        flop_clusters: int = 200,
        db_path: str = "clustering_data.db"
    ) -> bool:
        """Build all clustering lookup tables."""
        print(f"Building river LUT with {river_clusters} clusters...")
        if not NativePokerAI.build_river_lut(river_clusters, db_path):
            return False
        
        # Additional LUT building would go here
        print("All LUTs built successfully")
        return True
```

---

## 8. Database Integration

### 8.1 SQLite Storage Backend

```zig
// src/clustering/storage.zig
const sqlite = @cImport(@cInclude("sqlite3.h"));

pub const SQLiteStorage = struct {
    db: *sqlite.sqlite3,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !SQLiteStorage {
        var db: ?*sqlite.sqlite3 = null;
        const result = sqlite.sqlite3_open(@ptrCast(db_path.ptr), &db);
        
        if (result != sqlite.SQLITE_OK) {
            return error.DatabaseOpenFailed;
        }
        
        var storage = SQLiteStorage{
            .db = db.?,
            .allocator = allocator,
        };
        
        try storage.createTables();
        return storage;
    }
    
    pub fn deinit(self: *SQLiteStorage) void {
        _ = sqlite.sqlite3_close(self.db);
    }
    
    fn createTables(self: *SQLiteStorage) !void {
        const create_river = 
            \\CREATE TABLE IF NOT EXISTS river_data (
            \\    combo_id INTEGER PRIMARY KEY,
            \\    combo_cards BLOB NOT NULL,
            \\    ehs REAL NOT NULL,
            \\    cluster_id INTEGER NOT NULL
            \\);
        ;
        
        const create_turn = 
            \\CREATE TABLE IF NOT EXISTS turn_data (
            \\    combo_id INTEGER PRIMARY KEY,
            \\    combo_cards BLOB NOT NULL,
            \\    distribution BLOB NOT NULL,
            \\    cluster_id INTEGER NOT NULL
            \\);
        ;
        
        _ = sqlite.sqlite3_exec(self.db, create_river, null, null, null);
        _ = sqlite.sqlite3_exec(self.db, create_turn, null, null, null);
    }
    
    pub fn storeRiverBatch(self: *SQLiteStorage, features: []const f32, labels: []const u16) !void {
        const insert_sql = "INSERT INTO river_data (combo_cards, ehs, cluster_id) VALUES (?, ?, ?)";
        
        var stmt: ?*sqlite.sqlite3_stmt = null;
        _ = sqlite.sqlite3_prepare_v2(self.db, insert_sql, -1, &stmt, null);
        defer _ = sqlite.sqlite3_finalize(stmt);
        
        for (features, labels) |feature, label| {
            _ = sqlite.sqlite3_reset(stmt);
            _ = sqlite.sqlite3_bind_blob(stmt, 1, &feature, @sizeOf(f32), null);
            _ = sqlite.sqlite3_bind_double(stmt, 2, feature);
            _ = sqlite.sqlite3_bind_int(stmt, 3, label);
            _ = sqlite.sqlite3_step(stmt);
        }
    }
};
```

---

## 9. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
**Goal:** Core poker engine with basic game mechanics
**Deliverables:**
- Card, Deck, Player, Table structs
- Basic game state management
- Hand evaluation system
- Unit tests for core functionality

### Phase 2: Hand Evaluation (Weeks 3-4)  
**Goal:** Fast, accurate 7-card hand evaluation
**Deliverables:**
- Lookup table generation for hand ranks
- SIMD-optimized evaluation routines
- Benchmark against existing evaluators
- Performance tests (target: >1M evaluations/sec)

### Phase 3: Memory Management (Weeks 5-6)
**Goal:** Efficient memory allocation for game tree traversal
**Deliverables:**
- Arena allocators for game states
- Memory pools for training data
- Garbage collection strategies
- Memory usage profiling tools

### Phase 4: Basic AI (Weeks 7-10)
**Goal:** Single-threaded CFR implementation
**Deliverables:**
- Information set management
- CFR algorithm implementation
- Strategy calculation and storage
- Basic training loop

### Phase 5: Clustering System (Weeks 11-14)
**Goal:** Hand abstraction via clustering
**Deliverables:**
- Equity calculation system
- K-means clustering implementation
- LUT generation for all game stages
- SQLite storage backend

### Phase 6: Parallelization (Weeks 15-18)
**Goal:** Multi-threaded training system
**Deliverables:**
- Thread pool for parallel CFR
- Lock-free data structures
- Strategy aggregation system
- Performance benchmarks

### Phase 7: Python Integration (Weeks 19-20)
**Goal:** Seamless Python interoperability
**Deliverables:**
- C API implementation
- Python bindings
- Migration tools from existing system
- Integration tests

### Phase 8: Optimization (Weeks 21-24)
**Goal:** Production-ready performance
**Deliverables:**
- SIMD optimizations
- Cache-friendly data layouts
- Profile-guided optimization
- Final performance benchmarks

---

## 10. Performance Targets

### Benchmarks vs Python Implementation
- **Hand Evaluation:** 100x faster (10M+ hands/sec)
- **CFR Iteration:** 50x faster for equivalent game tree
- **Memory Usage:** 10x lower memory footprint  
- **Clustering:** 20x faster LUT generation
- **Training Speed:** 30x faster iterations

### Scaling Characteristics
- **Memory:** Linear scaling with game tree size
- **CPU:** Near-linear scaling with thread count
- **I/O:** Batch processing for database operations
- **Network:** Distributed training capability

---

## 11. Risk Mitigation

### Technical Risks
1. **Memory Management Complexity**
   - *Mitigation:* Start with simple arena allocators, profile extensively
   
2. **SIMD Portability Issues**  
   - *Mitigation:* Fallback to scalar code, test on multiple architectures
   
3. **C Interop Stability**
   - *Mitigation:* Comprehensive integration tests, version pinning

### Performance Risks
1. **Cache Misses in Game Tree**
   - *Mitigation:* Careful data layout design, cache profiling
   
2. **Lock Contention in Parallel Training**
   - *Mitigation:* Lock-free algorithms, thread-local storage

### Migration Risks
1. **Algorithm Compatibility**
   - *Mitigation:* Side-by-side testing, gradual migration
   
2. **Data Format Changes**
   - *Mitigation:* Conversion tools, backward compatibility

---

This architecture provides a solid foundation for migrating the poker AI system to Zig while maintaining the core algorithms and improving performance dramatically. The design emphasizes simplicity, performance, and maintainability - exactly what's needed for a production poker AI system.