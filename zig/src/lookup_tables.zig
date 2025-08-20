const std = @import("std");
const clustering = @import("clustering.zig");
const hand_eval = @import("hand_eval.zig");

// Define types locally to avoid circular imports
pub const Card = u32;
pub const HandRank = u16;
const PRIMES = [13]u8{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41 };
const MAX_STRAIGHT_FLUSH: HandRank = 10;
const MAX_FOUR_OF_A_KIND: HandRank = 166;
const MAX_FULL_HOUSE: HandRank = 322;
const MAX_FLUSH: HandRank = 1599;
const MAX_STRAIGHT: HandRank = 1609;
const MAX_THREE_OF_A_KIND: HandRank = 2467;
const MAX_TWO_PAIR: HandRank = 3325;
const MAX_PAIR: HandRank = 6185;
const MAX_HIGH_CARD: HandRank = 7462;

// Lookup table entry for hash maps
const LookupEntry = struct {
    prime_product: u64,
    rank: HandRank,
};

/// Compile-time lookup table generation
/// This generates the exact same tables as the Python implementation
pub const TableGenerator = struct {
    // Straight flush bit patterns (same as Python)
    const STRAIGHT_FLUSH_PATTERNS = [10]u32{
        7936,  // 0b1111100000000 - Royal flush (AKQJT)
        3968,  // 0b111110000000 - KQJT9
        1984,  // 0b11111000000 - QJT98
        992,   // 0b1111100000 - JT987
        496,   // 0b111110000 - T9876
        248,   // 0b11111000 - 98765
        124,   // 0b1111100 - 87654
        62,    // 0b111110 - 76543
        31,    // 0b11111 - 65432
        4111,  // 0b1000000001111 - 5432A (wheel)
    };

    /// Generate lexicographically next bit sequence
    /// Port of Python's bit hack for generating combinations
    fn getNextBitSequence(bits: u32) u32 {
        const t = (bits | (bits - 1)) + 1;
        return t | (((t & (~t + 1)) / (bits & (~bits + 1))) >> 1) - 1;
    }

    /// Generate all flush patterns (excluding straight flushes)
    fn generateFlushPatterns(allocator: std.mem.Allocator) ![]u32 {
        var patterns = std.ArrayList(u32).init(allocator);

        // Start with lowest 5-bit pattern (5 high straight)
        var current: u32 = 0b11111; // 31

        // Generate 1277 + 10 - 1 patterns (high cards + straights - 1)
        for (0..1286) |_| {
            current = getNextBitSequence(current);

            // Check if this pattern matches any straight flush
            var is_straight_flush = false;
            for (STRAIGHT_FLUSH_PATTERNS) |sf| {
                if (current == sf) {
                    is_straight_flush = true;
                    break;
                }
            }

            // Only add non-straight-flush patterns
            if (!is_straight_flush) {
                try patterns.append(current);
            }
        }

        // Reverse to rank from strongest to weakest
        std.mem.reverse(u32, patterns.items);
        return try patterns.toOwnedSlice();
    }

    /// Generate prime product from rankbits
    fn primeProductFromRankbits(rankbits: u32) u64 {
        var product: u64 = 1;
        var i: u5 = 0;
        while (i < 13) : (i += 1) {
            if ((rankbits & (@as(u32, 1) << i)) != 0) {
                product *= PRIMES[i];
            }
        }
        return product;
    }

    /// Generate flush lookup table entries
    fn generateFlushLookup(allocator: std.mem.Allocator) ![]LookupEntry {
        var entries = std.ArrayList(LookupEntry).init(allocator);

        // 1. Straight flushes (rank 1-10)
        for (STRAIGHT_FLUSH_PATTERNS, 0..) |pattern, i| {
            const prime_product = primeProductFromRankbits(pattern);
            try entries.append(LookupEntry{
                .prime_product = prime_product,
                .rank = @intCast(i + 1),
            });
        }

        // 2. Regular flushes (rank MAX_FULL_HOUSE + 1 onwards)
        const flush_patterns = try generateFlushPatterns(allocator);
        defer allocator.free(flush_patterns);

        for (flush_patterns, 0..) |pattern, i| {
            const prime_product = primeProductFromRankbits(pattern);
            try entries.append(LookupEntry{
                .prime_product = prime_product,
                .rank = @intCast(MAX_FULL_HOUSE + 1 + i),
            });
        }

        return try entries.toOwnedSlice();
    }

    /// Generate unsuited lookup table entries
    fn generateUnsuitedLookup(allocator: std.mem.Allocator) ![]LookupEntry {
        var entries = std.ArrayList(LookupEntry).init(allocator);

        // Rank ordering (same as Python)
        const backwards_ranks = [13]u8{ 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };

        var rank: HandRank = MAX_STRAIGHT_FLUSH + 1;

        // 1. Four of a Kind
        for (backwards_ranks) |quad_rank| {
            for (backwards_ranks) |kicker_rank| {
                if (quad_rank != kicker_rank) {
                    const product = std.math.pow(u64, PRIMES[quad_rank], 4) * PRIMES[kicker_rank];
                    try entries.append(LookupEntry{
                        .prime_product = product,
                        .rank = rank,
                    });
                    rank += 1;
                }
            }
        }

        // 2. Full House
        rank = MAX_FOUR_OF_A_KIND + 1;
        for (backwards_ranks) |trip_rank| {
            for (backwards_ranks) |pair_rank| {
                if (trip_rank != pair_rank) {
                    const product = std.math.pow(u64, PRIMES[trip_rank], 3) * 
                                  std.math.pow(u64, PRIMES[pair_rank], 2);
                    try entries.append(LookupEntry{
                        .prime_product = product,
                        .rank = rank,
                    });
                    rank += 1;
                }
            }
        }

        // 3. Straights (reuse straight flush patterns)
        rank = MAX_FLUSH + 1;
        for (STRAIGHT_FLUSH_PATTERNS) |pattern| {
            const product = primeProductFromRankbits(pattern);
            try entries.append(LookupEntry{
                .prime_product = product,
                .rank = rank,
            });
            rank += 1;
        }

        // 4. Three of a Kind
        rank = MAX_STRAIGHT + 1;
        for (backwards_ranks) |trip_rank| {
            // Generate all 2-combinations of remaining ranks for kickers
            for (backwards_ranks, 0..) |kicker1, i| {
                if (kicker1 == trip_rank) continue;
                for (backwards_ranks[i+1..]) |kicker2| {
                    if (kicker2 == trip_rank) continue;
                    const product = std.math.pow(u64, PRIMES[trip_rank], 3) * 
                                  PRIMES[kicker1] * PRIMES[kicker2];
                    try entries.append(LookupEntry{
                        .prime_product = product,
                        .rank = rank,
                    });
                    rank += 1;
                }
            }
        }

        // 5. Two Pair
        rank = MAX_THREE_OF_A_KIND + 1;
        for (backwards_ranks, 0..) |pair1, i| {
            for (backwards_ranks[i+1..]) |pair2| {
                for (backwards_ranks) |kicker| {
                    if (kicker != pair1 and kicker != pair2) {
                        const product = std.math.pow(u64, PRIMES[pair1], 2) *
                                      std.math.pow(u64, PRIMES[pair2], 2) *
                                      PRIMES[kicker];
                        try entries.append(LookupEntry{
                            .prime_product = product,
                            .rank = rank,
                        });
                        rank += 1;
                    }
                }
            }
        }

        // 6. One Pair
        rank = MAX_TWO_PAIR + 1;
        for (backwards_ranks) |pair_rank| {
            // Generate all 3-combinations of remaining ranks for kickers
            for (backwards_ranks, 0..) |k1, i| {
                if (k1 == pair_rank) continue;
                for (backwards_ranks[i+1..], 0..) |k2, j| {
                    if (k2 == pair_rank) continue;
                    for (backwards_ranks[i+j+2..]) |k3| {
                        if (k3 == pair_rank) continue;
                        const product = std.math.pow(u64, PRIMES[pair_rank], 2) *
                                      PRIMES[k1] * PRIMES[k2] * PRIMES[k3];
                        try entries.append(LookupEntry{
                            .prime_product = product,
                            .rank = rank,
                        });
                        rank += 1;
                    }
                }
            }
        }

        // 7. High Card (reuse flush patterns)
        rank = MAX_PAIR + 1;
        const flush_patterns = try generateFlushPatterns(allocator);
        defer allocator.free(flush_patterns);
        
        for (flush_patterns) |pattern| {
            const product = primeProductFromRankbits(pattern);
            try entries.append(LookupEntry{
                .prime_product = product,
                .rank = rank,
            });
            rank += 1;
        }

        return try entries.toOwnedSlice();
    }
};

/// Runtime lookup tables with hash maps for fast access
pub const Tables = struct {
    flush_map: std.HashMap(u64, HandRank, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    unsuited_map: std.HashMap(u64, HandRank, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),

    pub fn init() Tables {
        // For now, return empty hash maps
        // In a real implementation, these would be populated from compile-time generated data
        // Using a simple approach due to Zig's compile-time limitations with large data structures
        return Tables{
            .flush_map = std.HashMap(u64, HandRank, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(std.heap.page_allocator),
            .unsuited_map = std.HashMap(u64, HandRank, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(std.heap.page_allocator),
        };
    }

    /// Initialize lookup tables with computed values
    /// This should be called once at startup
    pub fn initTables(self: *Tables) !void {
        // Initialize hash maps with capacity estimates
        try self.flush_map.ensureTotalCapacity(1287);  // ~10 SFs + ~1277 flushes
        try self.unsuited_map.ensureTotalCapacity(6175); // ~6175 non-flush hands

        // Generate and populate flush lookup
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const flush_entries = try TableGenerator.generateFlushLookup(allocator);
        defer allocator.free(flush_entries);
        for (flush_entries) |entry| {
            try self.flush_map.put(entry.prime_product, entry.rank);
        }

        const unsuited_entries = try TableGenerator.generateUnsuitedLookup(allocator);
        defer allocator.free(unsuited_entries);
        for (unsuited_entries) |entry| {
            try self.unsuited_map.put(entry.prime_product, entry.rank);
        }
    }

    pub fn deinit(self: *Tables) void {
        self.flush_map.deinit();
        self.unsuited_map.deinit();
    }

    /// Look up hand rank for a flush
    pub fn getFlushRank(self: *const Tables, prime_product: u64) HandRank {
        return self.flush_map.get(prime_product) orelse MAX_HIGH_CARD;
    }

    /// Look up hand rank for non-flush hands
    pub fn getUnsuitedRank(self: *const Tables, prime_product: u64) HandRank {
        return self.unsuited_map.get(prime_product) orelse MAX_HIGH_CARD;
    }
};

// Compile-time verification of constants
comptime {
    // Verify straight flush patterns sum to expected total
    var total: u32 = 0;
    for (TableGenerator.STRAIGHT_FLUSH_PATTERNS) |pattern| {
        total += @popCount(pattern);
    }
    if (total != 50) @compileError("Straight flush patterns should have 50 total bits set (10 * 5)");
}

test "lookup table generation" {
    var tables = Tables.init();
    defer tables.deinit();
    
    try tables.initTables();
    
    // Test that tables are populated
    std.testing.expect(tables.flush_map.count() > 0) catch unreachable;
    std.testing.expect(tables.unsuited_map.count() > 0) catch unreachable;
}

test "prime product calculation" {
    // Test that prime products are calculated correctly
    const royal_flush_bits: u32 = 0b1111100000000; // AKQJT
    const product = TableGenerator.primeProductFromRankbits(royal_flush_bits);
    
    // Should be product of primes for A, K, Q, J, T
    const expected: u64 = 41 * 37 * 31 * 29 * 23;
    try std.testing.expect(product == expected);
}

/// AbstractionTable for poker hand and action abstraction in CFR
/// Reduces the state space by clustering similar hands and actions
pub const AbstractionTable = struct {
    // Hand abstraction buckets
    preflop_buckets: []u16,  // Maps 169 preflop hand combinations to buckets
    flop_buckets: std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    turn_buckets: std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    river_buckets: std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    
    // Clustering components
    preflop_clusterer: ?*clustering.PreflopClusterer,
    postflop_clusterer: ?*clustering.PostflopClusterer,
    cluster_storage: ?*clustering.ClusterStorage,
    
    // Action abstraction
    bet_sizes: []f64,  // Normalized bet sizes (e.g., [0.5, 1.0, 2.0] pot sizes)
    
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    // Configuration constants
    const NUM_PREFLOP_HANDS = 169;  // 13*13 = 169 unique preflop combinations
    const NUM_PREFLOP_BUCKETS = 8;  // Group into 8 strength categories
    const NUM_POSTFLOP_BUCKETS = 50; // Postflop bucketing
    const DEFAULT_BET_SIZES = [_]f64{ 0.5, 1.0, 2.0 }; // Half pot, pot, 2x pot
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        // Allocate preflop bucket array
        const preflop_buckets = try allocator.alloc(u16, NUM_PREFLOP_HANDS);
        
        // Allocate bet sizes
        const bet_sizes = try allocator.alloc(f64, DEFAULT_BET_SIZES.len);
        @memcpy(bet_sizes, &DEFAULT_BET_SIZES);
        
        // Initialize hash maps for postflop
        const flop_buckets = std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator);
        const turn_buckets = std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator);
        const river_buckets = std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator);
        
        var table = Self{
            .preflop_buckets = preflop_buckets,
            .flop_buckets = flop_buckets,
            .turn_buckets = turn_buckets,
            .river_buckets = river_buckets,
            .preflop_clusterer = null,
            .postflop_clusterer = null,
            .cluster_storage = null,
            .bet_sizes = bet_sizes,
            .allocator = allocator,
        };
        
        // Initialize preflop hand rankings (simplified)
        try table.initPreflopBuckets();
        
        return table;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.preflop_buckets);
        self.allocator.free(self.bet_sizes);
        self.flop_buckets.deinit();
        self.turn_buckets.deinit();
        self.river_buckets.deinit();
        
        if (self.preflop_clusterer) |clusterer| {
            clusterer.deinit();
            self.allocator.destroy(clusterer);
        }
        
        if (self.postflop_clusterer) |clusterer| {
            clusterer.deinit();
            self.allocator.destroy(clusterer);
        }
        
        if (self.cluster_storage) |storage| {
            storage.deinit();
            self.allocator.destroy(storage);
        }
    }
    
    /// Initialize preflop hand strength buckets
    /// Groups the 169 possible preflop hands into strength categories
    fn initPreflopBuckets(self: *Self) !void {
        // Simplified preflop hand strength categorization
        // This is a basic implementation - in practice, you'd use actual hand strength calculations
        
        var bucket_index: u16 = 0;
        
        // Premium hands (AA, KK, QQ, AK)
        for (0..4) |_| {
            self.preflop_buckets[bucket_index] = 0; // Strongest bucket
            bucket_index += 1;
        }
        
        // Strong hands (JJ, TT, AQ, AJ)
        for (0..15) |_| {
            self.preflop_buckets[bucket_index] = 1;
            bucket_index += 1;
        }
        
        // Good hands (99-77, AT, KQ, KJ)
        for (0..25) |_| {
            self.preflop_buckets[bucket_index] = 2;
            bucket_index += 1;
        }
        
        // Decent hands (66-22, A9-A2, KT-K2, QJ-Q2)
        for (0..35) |_| {
            self.preflop_buckets[bucket_index] = 3;
            bucket_index += 1;
        }
        
        // Marginal hands (Suited connectors, some broadway)
        for (0..40) |_| {
            self.preflop_buckets[bucket_index] = 4;
            bucket_index += 1;
        }
        
        // Weak hands (Suited gaps, weak offsuit)
        for (0..30) |_| {
            self.preflop_buckets[bucket_index] = 5;
            bucket_index += 1;
        }
        
        // Poor hands (Most offsuit hands)
        for (0..15) |_| {
            self.preflop_buckets[bucket_index] = 6;
            bucket_index += 1;
        }
        
        // Trash hands (72o, 83o, etc.)
        while (bucket_index < NUM_PREFLOP_HANDS) {
            self.preflop_buckets[bucket_index] = 7; // Weakest bucket
            bucket_index += 1;
        }
    }
    
    /// Get bucket for preflop hand combination
    /// hand_index should be 0-168 representing one of the 169 unique preflop combinations
    pub fn getPreflopBucket(self: *const Self, hand_index: u16) u16 {
        if (hand_index >= NUM_PREFLOP_HANDS) {
            return 7; // Default to weakest bucket for invalid hands
        }
        return self.preflop_buckets[hand_index];
    }
    
    /// Get bucket for postflop hand (simplified hash-based)
    /// In practice, this would use proper hand strength evaluation
    pub fn getPostflopBucket(self: *Self, hand_hash: u64, round: u8) u16 {
        const bucket_map = switch (round) {
            1 => &self.flop_buckets,   // Flop
            2 => &self.turn_buckets,   // Turn  
            3 => &self.river_buckets,  // River
            else => &self.flop_buckets, // Default to flop
        };
        
        // Check if we've already computed this bucket
        if (bucket_map.get(hand_hash)) |bucket| {
            return bucket;
        }
        
        // Simple hash-based bucketing (placeholder)
        // In practice, this would evaluate actual hand strength
        const bucket = @as(u16, @intCast(hand_hash % NUM_POSTFLOP_BUCKETS));
        
        // Cache the result
        bucket_map.put(hand_hash, bucket) catch {
            // If we can't cache, just return the bucket
            return bucket;
        };
        
        return bucket;
    }
    
    /// Abstract actions by reducing bet sizes to predefined options
    /// Returns the index of the closest allowed bet size
    pub fn abstractAction(self: *const Self, pot_size: f64, bet_amount: f64) u8 {
        if (bet_amount == 0.0) {
            return 0; // Check/fold action
        }
        
        const bet_ratio = bet_amount / pot_size;
        var closest_index: u8 = 0;
        var min_distance = @abs(bet_ratio - self.bet_sizes[0]);
        
        for (self.bet_sizes, 0..) |size, i| {
            const distance = @abs(bet_ratio - size);
            if (distance < min_distance) {
                min_distance = distance;
                closest_index = @intCast(i);
            }
        }
        
        return closest_index + 1; // +1 because 0 is reserved for check/fold
    }
    
    /// Get abstracted bet amount for a given action index
    pub fn getAbstractedBetSize(self: *const Self, action_index: u8, pot_size: f64) f64 {
        if (action_index == 0) {
            return 0.0; // Check/fold
        }
        
        const bet_index = action_index - 1;
        if (bet_index >= self.bet_sizes.len) {
            return pot_size; // Default to pot-sized bet
        }
        
        return self.bet_sizes[bet_index] * pot_size;
    }
    
    /// Get number of abstract actions (check/fold + bet sizes)
    pub fn getNumAbstractActions(self: *const Self) u8 {
        return @intCast(self.bet_sizes.len + 1); // +1 for check/fold
    }
    
    /// Create information set string with abstracted values
    /// This combines hand bucket and betting history into a compact representation
    pub fn createAbstractInfoSet(
        _: *const Self,
        allocator: std.mem.Allocator,
        hand_bucket: u16,
        betting_history: []const u8,
    ) ![]u8 {
        // Simple format: "bucket_history"
        // In practice, this might be more sophisticated
        const info_set = try std.fmt.allocPrint(
            allocator,
            "{d}_{s}",
            .{ hand_bucket, betting_history }
        );
        return info_set;
    }
    
    /// Initialize clustering with training data
    pub fn initClustering(
        self: *Self,
        evaluator: *hand_eval.HandEvaluator,
        n_preflop_clusters: usize,
        n_flop_clusters: usize,
        n_turn_clusters: usize,
        n_river_clusters: usize,
    ) !void {
        // Initialize preflop clusterer
        self.preflop_clusterer = try self.allocator.create(clustering.PreflopClusterer);
        self.preflop_clusterer.?.* = try clustering.PreflopClusterer.init(self.allocator);
        
        // Train preflop clusters with equity calculations
        try self.preflop_clusterer.?.trainWithEquity(
            evaluator,
            n_preflop_clusters,
            clustering.DEFAULT_N_SIMULATIONS,
        );
        
        // Initialize postflop clusterer
        self.postflop_clusterer = try self.allocator.create(clustering.PostflopClusterer);
        self.postflop_clusterer.?.* = clustering.PostflopClusterer.init(self.allocator, evaluator);
        
        // Initialize cluster storage
        self.cluster_storage = try self.allocator.create(clustering.ClusterStorage);
        self.cluster_storage.?.* = clustering.ClusterStorage.init(self.allocator);
        
        _ = n_flop_clusters;
        _ = n_turn_clusters;
        _ = n_river_clusters;
    }
    
    /// Get cluster ID for a hand using advanced clustering
    pub fn getHandCluster(
        self: *Self,
        hole_cards: [2]hand_eval.Card,
        board: []const hand_eval.Card,
    ) !u16 {
        if (board.len == 0) {
            // Preflop
            if (self.preflop_clusterer) |clusterer| {
                return clusterer.getCluster(hole_cards[0], hole_cards[1]);
            } else {
                // Fall back to simple bucketing
                const idx = clustering.PreflopClusterer.getCanonicalIndex(hole_cards[0], hole_cards[1]);
                return self.getPreflopBucket(@intCast(idx));
            }
        } else {
            // Postflop
            if (self.postflop_clusterer) |clusterer| {
                return try clusterer.getCluster(hole_cards, board);
            } else {
                // Fall back to hash-based bucketing
                var hash: u64 = 0;
                hash |= @as(u64, hole_cards[0]) << 32;
                hash |= @as(u64, hole_cards[1]);
                for (board) |card| {
                    hash ^= @as(u64, card) << @intCast(card & 0x1F);
                }
                return self.getPostflopBucket(hash, @intCast(board.len - 2));
            }
        }
    }
    
    /// Save clustering data to file
    pub fn saveClusteringData(self: *Self, path: []const u8) !void {
        if (self.cluster_storage) |storage| {
            // Copy current clustering data to storage
            if (self.preflop_clusterer) |clusterer| {
                storage.preflop_clusters = try self.allocator.dupe(u8, clusterer.clusters);
            }
            
            // Save to file
            try storage.save(path);
        }
    }
    
    /// Load clustering data from file
    pub fn loadClusteringData(self: *Self, path: []const u8) !void {
        if (self.cluster_storage == null) {
            self.cluster_storage = try self.allocator.create(clustering.ClusterStorage);
            self.cluster_storage.?.* = clustering.ClusterStorage.init(self.allocator);
        }
        
        try self.cluster_storage.?.load(path);
        
        // Update clusterers with loaded data
        if (self.cluster_storage.?.preflop_clusters.len > 0) {
            if (self.preflop_clusterer == null) {
                self.preflop_clusterer = try self.allocator.create(clustering.PreflopClusterer);
                self.preflop_clusterer.?.* = try clustering.PreflopClusterer.init(self.allocator);
            }
            @memcpy(self.preflop_clusterer.?.clusters, self.cluster_storage.?.preflop_clusters);
        }
    }
};

test "abstraction table initialization" {
    var table = try AbstractionTable.init(std.testing.allocator);
    defer table.deinit();
    
    // Check preflop buckets are initialized
    try std.testing.expectEqual(@as(usize, AbstractionTable.NUM_PREFLOP_HANDS), table.preflop_buckets.len);
    
    // Check bet sizes are set
    try std.testing.expect(table.bet_sizes.len > 0);
    try std.testing.expectEqual(@as(f64, 0.5), table.bet_sizes[0]);
}

test "preflop bucket assignment" {
    var table = try AbstractionTable.init(std.testing.allocator);
    defer table.deinit();
    
    // Premium hands should be in bucket 0
    try std.testing.expectEqual(@as(u16, 0), table.getPreflopBucket(0));
    try std.testing.expectEqual(@as(u16, 0), table.getPreflopBucket(1));
    
    // Invalid hand should return weakest bucket
    try std.testing.expectEqual(@as(u16, 7), table.getPreflopBucket(200));
}

test "postflop bucket caching" {
    var table = try AbstractionTable.init(std.testing.allocator);
    defer table.deinit();
    
    const hand_hash: u64 = 12345;
    const bucket1 = table.getPostflopBucket(hand_hash, 1); // Flop
    const bucket2 = table.getPostflopBucket(hand_hash, 1); // Same hand, same round
    
    // Should return the same bucket (cached)
    try std.testing.expectEqual(bucket1, bucket2);
}

test "action abstraction" {
    var table = try AbstractionTable.init(std.testing.allocator);
    defer table.deinit();
    
    const pot_size: f64 = 100.0;
    
    // Check/fold
    try std.testing.expectEqual(@as(u8, 0), table.abstractAction(pot_size, 0.0));
    
    // Half pot bet should map to index 1 (half pot size)
    try std.testing.expectEqual(@as(u8, 1), table.abstractAction(pot_size, 50.0));
    
    // Pot sized bet should map to index 2
    try std.testing.expectEqual(@as(u8, 2), table.abstractAction(pot_size, 100.0));
}

test "abstracted bet size retrieval" {
    var table = try AbstractionTable.init(std.testing.allocator);
    defer table.deinit();
    
    const pot_size: f64 = 200.0;
    
    // Check/fold should return 0
    try std.testing.expectEqual(@as(f64, 0.0), table.getAbstractedBetSize(0, pot_size));
    
    // Half pot bet
    try std.testing.expectEqual(@as(f64, 100.0), table.getAbstractedBetSize(1, pot_size));
    
    // Pot sized bet
    try std.testing.expectEqual(@as(f64, 200.0), table.getAbstractedBetSize(2, pot_size));
}

test "info set creation" {
    var table = try AbstractionTable.init(std.testing.allocator);
    defer table.deinit();
    
    const betting_history = "cr"; // call, raise
    const info_set = try table.createAbstractInfoSet(
        std.testing.allocator,
        5, // bucket
        betting_history,
    );
    defer std.testing.allocator.free(info_set);
    
    try std.testing.expectEqualStrings("5_cr", info_set);
}

test "straight flush patterns" {
    // Verify each straight flush pattern has exactly 5 bits set
    for (TableGenerator.STRAIGHT_FLUSH_PATTERNS) |pattern| {
        try std.testing.expect(@popCount(pattern) == 5);
    }
}