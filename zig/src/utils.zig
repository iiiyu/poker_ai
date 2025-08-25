// Common utilities for poker AI system
// Bit manipulation, hashing, and other performance utilities

const std = @import("std");

// Fast bit manipulation utilities
pub const BitUtils = struct {
    // Count number of set bits (population count)
    pub fn popcount(value: u64) u32 {
        return @popCount(value);
    }

    // Find position of least significant bit
    pub fn lsb(value: u64) u32 {
        return @ctz(value);
    }

    // Find position of most significant bit
    pub fn msb(value: u64) u32 {
        return 63 - @clz(value);
    }

    // Extract bit at position
    pub fn getBit(value: u64, position: u6) bool {
        return (value >> position) & 1 == 1;
    }

    // Set bit at position
    pub fn setBit(value: u64, position: u6) u64 {
        return value | (@as(u64, 1) << position);
    }

    // Clear bit at position
    pub fn clearBit(value: u64, position: u6) u64 {
        return value & ~(@as(u64, 1) << position);
    }

    // Toggle bit at position
    pub fn toggleBit(value: u64, position: u6) u64 {
        return value ^ (@as(u64, 1) << position);
    }

    // Create mask with bits set from start to end (inclusive)
    pub fn createMask(start: u6, end: u6) u64 {
        if (start > end) return 0;
        const len = end - start + 1;
        if (len >= 64) return std.math.maxInt(u64);

        const mask = (@as(u64, 1) << @intCast(len)) - 1;
        return mask << start;
    }
};

// Fast hashing utilities for poker contexts
pub const HashUtils = struct {
    // Fast hash for card combinations (5-7 cards)
    pub fn hashCards(cards: []const u8) u64 {
        var hash: u64 = 0;
        for (cards) |card| {
            hash = hash * 53 + card;
        }
        return hash;
    }

    // Perfect hash for hole card combinations (169 unique)
    pub fn hashHoleCards(card1: u8, card2: u8) u8 {
        const rank1 = card1 >> 2;
        const rank2 = card2 >> 2;
        const suit1 = card1 & 3;
        const suit2 = card2 & 3;

        const high_rank = @max(rank1, rank2);
        const low_rank = @min(rank1, rank2);

        if (rank1 == rank2) {
            return high_rank; // Pairs: 0-12
        }

        const is_suited = suit1 == suit2;
        const base_index = high_rank * 12 + low_rank;

        return if (is_suited)
            13 + @as(u8, @intCast(base_index))
        else
            91 + @as(u8, @intCast(base_index));
    }

    // Combine multiple hash values
    pub fn combineHashes(hashes: []const u64) u64 {
        var result: u64 = 0;
        for (hashes) |hash| {
            result ^= hash + 0x9e3779b9 + (result << 6) + (result >> 2);
        }
        return result;
    }

    // FNV-1a hash for strings/byte arrays
    pub fn fnvHash(data: []const u8) u64 {
        var hash: u64 = 0xcbf29ce484222325;
        for (data) |byte| {
            hash ^= byte;
            hash *%= 0x100000001b3;
        }
        return hash;
    }
};

// Memory management utilities
pub const MemoryUtils = struct {
    // Arena allocator for temporary allocations
    pub const ScratchArena = struct {
        arena: std.heap.ArenaAllocator,

        const Self = @This();

        pub fn init(backing_allocator: std.mem.Allocator) Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(backing_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return self.arena.allocator();
        }

        pub fn reset(self: *Self) void {
            _ = self.arena.reset(.retain_capacity);
        }
    };

    // Pool allocator for fixed-size objects
    pub fn FixedPool(comptime T: type) type {
        return struct {
            pool: std.heap.MemoryPool(T),

            const Self = @This();

            pub fn init(backing_allocator: std.mem.Allocator) Self {
                return Self{
                    .pool = std.heap.MemoryPool(T).init(backing_allocator),
                };
            }

            pub fn deinit(self: *Self) void {
                self.pool.deinit();
            }

            pub fn create(self: *Self) !*T {
                return self.pool.create();
            }

            pub fn destroy(self: *Self, item: *T) void {
                self.pool.destroy(item);
            }
        };
    }

    // Get memory usage statistics
    pub fn getMemoryStats(allocator: std.mem.Allocator) MemoryStats {
        _ = allocator;
        // This would be implemented based on allocator type
        return MemoryStats{
            .allocated_bytes = 0,
            .peak_bytes = 0,
            .allocation_count = 0,
        };
    }
};

pub const MemoryStats = struct {
    allocated_bytes: usize,
    peak_bytes: usize,
    allocation_count: usize,
};

// Random number utilities optimized for poker
pub const RandomUtils = struct {
    // Fast random number generator for simulations
    pub const FastRng = struct {
        state: u64,

        const Self = @This();

        pub fn init(seed: u64) Self {
            return Self{ .state = seed };
        }

        pub fn next(self: *Self) u64 {
            // Xorshift64*
            self.state ^= self.state >> 12;
            self.state ^= self.state << 25;
            self.state ^= self.state >> 27;
            return self.state *% 0x2545F4914F6CDD1D;
        }

        pub fn range(self: *Self, min_val: u64, max_val: u64) u64 {
            if (min_val >= max_val) return min_val;
            return min_val + (self.next() % (max_val - min_val));
        }

        pub fn float(self: *Self) f64 {
            const bits = self.next() >> 11; // Use top 53 bits
            return @as(f64, @floatFromInt(bits)) / (1 << 53);
        }

        pub fn shuffle(self: *Self, comptime T: type, slice: []T) void {
            if (slice.len <= 1) return;

            var i = slice.len - 1;
            while (i > 0) {
                const j = self.range(0, i + 1);
                std.mem.swap(T, &slice[i], &slice[j]);
                i -= 1;
            }
        }
    };

    // Weighted random selection
    pub fn weightedChoice(rng: *FastRng, weights: []const f64) usize {
        var total_weight: f64 = 0;
        for (weights) |weight| {
            total_weight += weight;
        }

        if (total_weight <= 0) return 0;

        const rand_val = rng.float() * total_weight;
        var cumulative: f64 = 0;

        for (weights, 0..) |weight, i| {
            cumulative += weight;
            if (rand_val <= cumulative) {
                return i;
            }
        }

        return weights.len - 1;
    }
};

// Performance measurement utilities
pub const PerfUtils = struct {
    // Simple timer for benchmarking
    pub const Timer = struct {
        start_time: i64,

        const Self = @This();

        pub fn start() Self {
            return Self{
                .start_time = std.time.nanoTimestamp(),
            };
        }

        pub fn elapsed(self: Self) i64 {
            return std.time.nanoTimestamp() - self.start_time;
        }

        pub fn elapsedMs(self: Self) f64 {
            return @as(f64, @floatFromInt(self.elapsed())) / 1_000_000.0;
        }

        pub fn elapsedUs(self: Self) f64 {
            return @as(f64, @floatFromInt(self.elapsed())) / 1_000.0;
        }
    };

    // Running statistics for performance monitoring
    pub const RunningStats = struct {
        count: u64,
        sum: f64,
        sum_squares: f64,
        min_val: f64,
        max_val: f64,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .count = 0,
                .sum = 0,
                .sum_squares = 0,
                .min_val = std.math.inf(f64),
                .max_val = -std.math.inf(f64),
            };
        }

        pub fn add(self: *Self, value: f64) void {
            self.count += 1;
            self.sum += value;
            self.sum_squares += value * value;
            self.min_val = @min(self.min_val, value);
            self.max_val = @max(self.max_val, value);
        }

        pub fn mean(self: Self) f64 {
            return if (self.count > 0) self.sum / @as(f64, @floatFromInt(self.count)) else 0;
        }

        pub fn variance(self: Self) f64 {
            if (self.count <= 1) return 0;
            const mean_val = self.mean();
            return (self.sum_squares - @as(f64, @floatFromInt(self.count)) * mean_val * mean_val) / @as(f64, @floatFromInt(self.count - 1));
        }

        pub fn stddev(self: Self) f64 {
            return @sqrt(self.variance());
        }
    };
};

// String utilities for information sets and debugging
pub const StringUtils = struct {
    // Convert cards to string representation
    pub fn cardsToString(allocator: std.mem.Allocator, cards: []const u8) ![]u8 {
        if (cards.len == 0) return try allocator.dupe(u8, "");

        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        const ranks = "23456789TJQKA";
        const suits = "cdhs";

        for (cards, 0..) |card, i| {
            if (i > 0) try result.append(' ');

            const rank = card >> 2;
            const suit = card & 3;

            if (rank < ranks.len and suit < suits.len) {
                try result.append(ranks[rank]);
                try result.append(suits[suit]);
            } else {
                try result.appendSlice("??");
            }
        }

        return result.toOwnedSlice();
    }

    // Parse card from string (e.g., "As" -> ace of spades)
    pub fn parseCard(card_str: []const u8) ?u8 {
        if (card_str.len != 2) return null;

        const rank_char = card_str[0];
        const suit_char = card_str[1];

        const rank = switch (rank_char) {
            '2'...'9' => rank_char - '2',
            'T', 't' => 8,
            'J', 'j' => 9,
            'Q', 'q' => 10,
            'K', 'k' => 11,
            'A', 'a' => 12,
            else => return null,
        };

        const suit = switch (suit_char) {
            'c', 'C' => 0,
            'd', 'D' => 1,
            'h', 'H' => 2,
            's', 'S' => 3,
            else => return null,
        };

        return (rank << 2) | suit;
    }

    // Format action to string
    pub fn actionToString(allocator: std.mem.Allocator, action_type: u8, amount: u32) ![]u8 {
        return switch (action_type) {
            0 => try allocator.dupe(u8, "fold"),
            1 => try allocator.dupe(u8, "call"),
            2 => try std.fmt.allocPrint(allocator, "raise({d})", .{amount}),
            3 => try allocator.dupe(u8, "check"),
            4 => try std.fmt.allocPrint(allocator, "all-in({d})", .{amount}),
            else => try allocator.dupe(u8, "unknown"),
        };
    }
};

test "bit utilities" {
    const testing = std.testing;

    try testing.expectEqual(@as(u32, 3), BitUtils.popcount(0b1011));
    try testing.expectEqual(@as(u32, 0), BitUtils.lsb(0b1000));
    try testing.expectEqual(@as(u32, 3), BitUtils.msb(0b1000));

    try testing.expect(BitUtils.getBit(0b1010, 1));
    try testing.expect(!BitUtils.getBit(0b1010, 0));

    try testing.expectEqual(@as(u64, 0b1011), BitUtils.setBit(0b1001, 1));
    try testing.expectEqual(@as(u64, 0b1001), BitUtils.clearBit(0b1011, 1));
}

test "hash utilities" {
    const testing = std.testing;

    const cards = [_]u8{ 0, 1, 2, 3, 4 };
    const hash1 = HashUtils.hashCards(&cards);
    const hash2 = HashUtils.hashCards(&cards);
    try testing.expectEqual(hash1, hash2);

    // Test hole card hashing
    const ace_spades = (12 << 2) | 3;
    const ace_clubs = (12 << 2) | 0;
    const hash_aa = HashUtils.hashHoleCards(ace_spades, ace_clubs);
    try testing.expect(hash_aa < 169);
}

test "random utilities" {
    const testing = std.testing;

    var rng = RandomUtils.FastRng.init(12345);

    const val1 = rng.next();
    const val2 = rng.next();
    try testing.expect(val1 != val2);

    const range_val = rng.range(10, 20);
    try testing.expect(range_val >= 10 and range_val < 20);

    const float_val = rng.float();
    try testing.expect(float_val >= 0.0 and float_val < 1.0);
}

test "performance utilities" {
    const testing = std.testing;

    var timer = PerfUtils.Timer.start();
    std.time.sleep(1000000); // 1ms
    const elapsed = timer.elapsedUs();
    try testing.expect(elapsed >= 900); // Should be at least 900us

    var stats = PerfUtils.RunningStats.init();
    stats.add(1.0);
    stats.add(2.0);
    stats.add(3.0);

    try testing.expectApproxEqAbs(@as(f64, 2.0), stats.mean(), 0.001);
}

test "string utilities" {
    const testing = std.testing;

    const ace_spades = (12 << 2) | 3; // Ace of spades
    const cards = [_]u8{ace_spades};

    const card_str = try StringUtils.cardsToString(testing.allocator, &cards);
    defer testing.allocator.free(card_str);

    try testing.expectEqualStrings("As", card_str);

    const parsed = StringUtils.parseCard("As");
    try testing.expectEqual(ace_spades, parsed.?);
}
