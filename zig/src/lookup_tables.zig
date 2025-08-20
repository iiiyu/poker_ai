const std = @import("std");

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
    fn generateFlushPatterns(comptime allocator: std.mem.Allocator) []u32 {
        var patterns = std.ArrayList(u32).init(allocator);
        defer patterns.deinit();

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
                patterns.append(current) catch unreachable;
            }
        }

        // Reverse to rank from strongest to weakest
        std.mem.reverse(u32, patterns.items);
        return patterns.toOwnedSlice() catch unreachable;
    }

    /// Generate prime product from rankbits at compile time
    fn primeProductFromRankbits(rankbits: u32) u64 {
        var product: u64 = 1;
        comptime var i: u5 = 0;
        inline while (i < 13) : (i += 1) {
            if ((rankbits & (@as(u32, 1) << i)) != 0) {
                product *= PRIMES[i];
            }
        }
        return product;
    }

    /// Generate flush lookup table entries at compile time
    fn generateFlushLookup(comptime allocator: std.mem.Allocator) []LookupEntry {
        var entries = std.ArrayList(LookupEntry).init(allocator);
        defer entries.deinit();

        // 1. Straight flushes (rank 1-10)
        for (STRAIGHT_FLUSH_PATTERNS, 0..) |pattern, i| {
            const prime_product = primeProductFromRankbits(pattern);
            entries.append(LookupEntry{
                .prime_product = prime_product,
                .rank = @intCast(i + 1),
            }) catch unreachable;
        }

        // 2. Regular flushes (rank MAX_FULL_HOUSE + 1 onwards)
        const flush_patterns = generateFlushPatterns(allocator);
        defer allocator.free(flush_patterns);

        for (flush_patterns, 0..) |pattern, i| {
            const prime_product = primeProductFromRankbits(pattern);
            entries.append(LookupEntry{
                .prime_product = prime_product,
                .rank = @intCast(MAX_FULL_HOUSE + 1 + i),
            }) catch unreachable;
        }

        return entries.toOwnedSlice() catch unreachable;
    }

    /// Generate unsuited lookup table entries at compile time
    fn generateUnsuitedLookup(comptime allocator: std.mem.Allocator) []LookupEntry {
        var entries = std.ArrayList(LookupEntry).init(allocator);
        defer entries.deinit();

        // Rank ordering (same as Python)
        const backwards_ranks = [13]u8{ 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };

        var rank: HandRank = MAX_STRAIGHT_FLUSH + 1;

        // 1. Four of a Kind
        for (backwards_ranks) |quad_rank| {
            for (backwards_ranks) |kicker_rank| {
                if (quad_rank != kicker_rank) {
                    const product = std.math.pow(u64, PRIMES[quad_rank], 4) * PRIMES[kicker_rank];
                    entries.append(LookupEntry{
                        .prime_product = product,
                        .rank = rank,
                    }) catch unreachable;
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
                    entries.append(LookupEntry{
                        .prime_product = product,
                        .rank = rank,
                    }) catch unreachable;
                    rank += 1;
                }
            }
        }

        // 3. Straights (reuse straight flush patterns)
        rank = MAX_FLUSH + 1;
        for (STRAIGHT_FLUSH_PATTERNS) |pattern| {
            const product = primeProductFromRankbits(pattern);
            entries.append(LookupEntry{
                .prime_product = product,
                .rank = rank,
            }) catch unreachable;
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
                    entries.append(LookupEntry{
                        .prime_product = product,
                        .rank = rank,
                    }) catch unreachable;
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
                        entries.append(LookupEntry{
                            .prime_product = product,
                            .rank = rank,
                        }) catch unreachable;
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
                        entries.append(LookupEntry{
                            .prime_product = product,
                            .rank = rank,
                        }) catch unreachable;
                        rank += 1;
                    }
                }
            }
        }

        // 7. High Card (reuse flush patterns)
        rank = MAX_PAIR + 1;
        const flush_patterns = generateFlushPatterns(allocator);
        defer allocator.free(flush_patterns);
        
        for (flush_patterns) |pattern| {
            const product = primeProductFromRankbits(pattern);
            entries.append(LookupEntry{
                .prime_product = product,
                .rank = rank,
            }) catch unreachable;
            rank += 1;
        }

        return entries.toOwnedSlice() catch unreachable;
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

        const flush_entries = TableGenerator.generateFlushLookup(allocator);
        for (flush_entries) |entry| {
            try self.flush_map.put(entry.prime_product, entry.rank);
        }

        const unsuited_entries = TableGenerator.generateUnsuitedLookup(allocator);
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

test "straight flush patterns" {
    // Verify each straight flush pattern has exactly 5 bits set
    for (TableGenerator.STRAIGHT_FLUSH_PATTERNS) |pattern| {
        try std.testing.expect(@popCount(pattern) == 5);
    }
}