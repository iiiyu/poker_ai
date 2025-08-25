const std = @import("std");
const builtin = @import("builtin");
const LookupTables = @import("lookup_tables.zig");

// Card representation using the same bit packing as Python implementation
// 32-bit integer with specific bit layout:
//   bitrank     suit rank   prime
// +--------+--------+--------+--------+
// |xxxbbbbb|bbbbbbbb|cdhsrrrr|xxpppppp|
// +--------+--------+--------+--------+

pub const Card = u32;
pub const HandRank = u16;

// Rank constants
pub const STR_RANKS = "23456789TJQKA";
pub const PRIMES = [13]u8{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41 };

// Suit bit patterns (same as Python)
pub const SUIT_SPADES: u32 = 1;
pub const SUIT_HEARTS: u32 = 2;
pub const SUIT_DIAMONDS: u32 = 4;
pub const SUIT_CLUBS: u32 = 8;

// Hand strength thresholds (same as Python)
pub const MAX_STRAIGHT_FLUSH: HandRank = 10;
pub const MAX_FOUR_OF_A_KIND: HandRank = 166;
pub const MAX_FULL_HOUSE: HandRank = 322;
pub const MAX_FLUSH: HandRank = 1599;
pub const MAX_STRAIGHT: HandRank = 1609;
pub const MAX_THREE_OF_A_KIND: HandRank = 2467;
pub const MAX_TWO_PAIR: HandRank = 3325;
pub const MAX_PAIR: HandRank = 6185;
pub const MAX_HIGH_CARD: HandRank = 7462;

// Hand type enumeration
pub const HandType = enum(u8) {
    straight_flush = 1,
    four_of_a_kind = 2,
    full_house = 3,
    flush = 4,
    straight = 5,
    three_of_a_kind = 6,
    two_pair = 7,
    pair = 8,
    high_card = 9,
};

/// Card creation and manipulation functions
pub const CardOps = struct {
    /// Create a card from string representation (e.g., "As", "2h", "Kd", "Tc")
    pub fn fromString(comptime str: []const u8) Card {
        if (str.len != 2) @compileError("Card string must be exactly 2 characters");

        const rank_char = str[0];
        const suit_char = str[1];

        // Convert rank character to rank integer
        const rank_int = comptime blk: {
            for (STR_RANKS, 0..) |r, i| {
                if (r == rank_char) break :blk @as(u32, @intCast(i));
            }
            @compileError("Invalid rank character: " ++ [1]u8{rank_char});
        };

        // Convert suit character to suit integer
        const suit_int = comptime switch (suit_char) {
            's' => SUIT_SPADES,
            'h' => SUIT_HEARTS,
            'd' => SUIT_DIAMONDS,
            'c' => SUIT_CLUBS,
            else => @compileError("Invalid suit character: " ++ [1]u8{suit_char}),
        };

        const rank_prime = PRIMES[rank_int];
        const bitrank: u32 = @as(u32, 1) << @intCast(rank_int + 16);
        const suit = suit_int << 12;
        const rank = rank_int << 8;

        return bitrank | suit | rank | rank_prime;
    }

    /// Create a card from string representation at runtime
    pub fn fromStringRuntime(str: []const u8) !Card {
        if (str.len != 2) return error.InvalidCardString;

        const rank_char = str[0];
        const suit_char = str[1];

        // Convert rank character to rank integer
        const rank_int: u32 = for (STR_RANKS, 0..) |r, i| {
            if (r == rank_char) break @intCast(i);
        } else return error.InvalidRank;

        // Convert suit character to suit integer
        const suit_int: u32 = switch (suit_char) {
            's' => SUIT_SPADES,
            'h' => SUIT_HEARTS,
            'd' => SUIT_DIAMONDS,
            'c' => SUIT_CLUBS,
            else => return error.InvalidSuit,
        };

        const rank_prime = PRIMES[rank_int];
        const bitrank: u32 = @as(u32, 1) << @intCast(rank_int + 16);
        const suit = suit_int << 12;
        const rank = rank_int << 8;

        return bitrank | suit | rank | rank_prime;
    }

    /// Extract rank integer from card (0-12, where 0=2, 12=A)
    pub inline fn getRank(card: Card) u8 {
        return @intCast((card >> 8) & 0xF);
    }

    /// Extract suit integer from card
    pub inline fn getSuit(card: Card) u8 {
        return @intCast((card >> 12) & 0xF);
    }

    /// Extract bitrank from card (used for flush detection)
    pub inline fn getBitrank(card: Card) u32 {
        return (card >> 16) & 0x1FFF;
    }

    /// Extract prime number from card
    pub inline fn getPrime(card: Card) u8 {
        return @intCast(card & 0x3F);
    }

    /// Calculate prime product from a hand of cards
    pub fn primeProductFromHand(cards: []const Card) u64 {
        var product: u64 = 1;
        for (cards) |card| {
            product *= getPrime(card);
        }
        return product;
    }

    /// Calculate prime product from rankbits (for flush evaluation)
    pub fn primeProductFromRankbits(rankbits: u32) u64 {
        var product: u64 = 1;
        var i: u5 = 0;
        while (i < 13) : (i += 1) {
            if ((rankbits & (@as(u32, 1) << i)) != 0) {
                product *= PRIMES[i];
            }
        }
        return product;
    }

    /// Create a card from rank and suit
    pub fn new(rank: u32, suit: u32) Card {
        const rank_prime = PRIMES[rank];
        const bitrank: u32 = @as(u32, 1) << @intCast(rank + 16);
        const suit_shifted = suit << 12;
        const rank_shifted = rank << 8;

        return bitrank | suit_shifted | rank_shifted | rank_prime;
    }

    /// Create a card from index (0-51)
    pub fn fromIndex(index: u32) Card {
        const rank = index % 13;
        const suit = index / 13;
        return new(rank, @as(u32, 1) << @intCast(suit));
    }
};

/// High-performance hand evaluator
pub const HandEvaluator = struct {
    lookup_tables: LookupTables.Tables,

    pub fn init() HandEvaluator {
        var tables = LookupTables.Tables.init();
        // Initialize the tables with actual data
        tables.initTables() catch {
            // If initialization fails, return with empty tables
            // This will cause all lookups to return MAX_HIGH_CARD
            std.debug.print("WARNING: Failed to initialize lookup tables\n", .{});
        };
        return HandEvaluator{
            .lookup_tables = tables,
        };
    }

    /// Evaluate a 5-card hand and return hand strength rank (1 = best, 7462 = worst)
    pub fn evaluateFive(self: *const HandEvaluator, cards: [5]Card) HandRank {
        // Check for flush by ANDing all suit bits
        const flush_check = cards[0] & cards[1] & cards[2] & cards[3] & cards[4] & 0xF000;

        if (flush_check != 0) {
            // It's a flush - use flush lookup table
            const hand_or = (cards[0] | cards[1] | cards[2] | cards[3] | cards[4]) >> 16;
            const prime = CardOps.primeProductFromRankbits(hand_or);
            return self.lookup_tables.getFlushRank(prime);
        } else {
            // Not a flush - use unsuited lookup table
            const prime = CardOps.primeProductFromHand(&cards);
            return self.lookup_tables.getUnsuitedRank(prime);
        }
    }

    /// Evaluate a 6-card hand (chooses best 5-card combination)
    pub fn evaluateSix(self: *const HandEvaluator, cards: [6]Card) HandRank {
        var best_rank: HandRank = MAX_HIGH_CARD;

        // Check all (6 choose 5) = 6 combinations
        const combinations = [6][5]usize{
            [5]usize{ 0, 1, 2, 3, 4 },
            [5]usize{ 0, 1, 2, 3, 5 },
            [5]usize{ 0, 1, 2, 4, 5 },
            [5]usize{ 0, 1, 3, 4, 5 },
            [5]usize{ 0, 2, 3, 4, 5 },
            [5]usize{ 1, 2, 3, 4, 5 },
        };

        for (combinations) |combo| {
            const hand = [5]Card{ cards[combo[0]], cards[combo[1]], cards[combo[2]], cards[combo[3]], cards[combo[4]] };
            const rank = self.evaluateFive(hand);
            if (rank < best_rank) {
                best_rank = rank;
            }
        }

        return best_rank;
    }

    /// Evaluate a 7-card hand (chooses best 5-card combination)
    pub fn evaluateSeven(self: *const HandEvaluator, cards: [7]Card) HandRank {
        var best_rank: HandRank = MAX_HIGH_CARD;

        // Check all (7 choose 5) = 21 combinations
        const combinations = [21][5]usize{
            [5]usize{ 0, 1, 2, 3, 4 }, [5]usize{ 0, 1, 2, 3, 5 }, [5]usize{ 0, 1, 2, 3, 6 },
            [5]usize{ 0, 1, 2, 4, 5 }, [5]usize{ 0, 1, 2, 4, 6 }, [5]usize{ 0, 1, 2, 5, 6 },
            [5]usize{ 0, 1, 3, 4, 5 }, [5]usize{ 0, 1, 3, 4, 6 }, [5]usize{ 0, 1, 3, 5, 6 },
            [5]usize{ 0, 1, 4, 5, 6 }, [5]usize{ 0, 2, 3, 4, 5 }, [5]usize{ 0, 2, 3, 4, 6 },
            [5]usize{ 0, 2, 3, 5, 6 }, [5]usize{ 0, 2, 4, 5, 6 }, [5]usize{ 0, 3, 4, 5, 6 },
            [5]usize{ 1, 2, 3, 4, 5 }, [5]usize{ 1, 2, 3, 4, 6 }, [5]usize{ 1, 2, 3, 5, 6 },
            [5]usize{ 1, 2, 4, 5, 6 }, [5]usize{ 1, 3, 4, 5, 6 }, [5]usize{ 2, 3, 4, 5, 6 },
        };

        for (combinations) |combo| {
            const hand = [5]Card{ cards[combo[0]], cards[combo[1]], cards[combo[2]], cards[combo[3]], cards[combo[4]] };
            const rank = self.evaluateFive(hand);
            if (rank < best_rank) {
                best_rank = rank;
            }
        }

        return best_rank;
    }

    /// Get hand type from rank
    pub fn getHandType(rank: HandRank) HandType {
        if (rank <= MAX_STRAIGHT_FLUSH) return .straight_flush;
        if (rank <= MAX_FOUR_OF_A_KIND) return .four_of_a_kind;
        if (rank <= MAX_FULL_HOUSE) return .full_house;
        if (rank <= MAX_FLUSH) return .flush;
        if (rank <= MAX_STRAIGHT) return .straight;
        if (rank <= MAX_THREE_OF_A_KIND) return .three_of_a_kind;
        if (rank <= MAX_TWO_PAIR) return .two_pair;
        if (rank <= MAX_PAIR) return .pair;
        return .high_card;
    }

    /// Convert hand type to string
    pub fn handTypeToString(hand_type: HandType) []const u8 {
        return switch (hand_type) {
            .straight_flush => "Straight Flush",
            .four_of_a_kind => "Four of a Kind",
            .full_house => "Full House",
            .flush => "Flush",
            .straight => "Straight",
            .three_of_a_kind => "Three of a Kind",
            .two_pair => "Two Pair",
            .pair => "Pair",
            .high_card => "High Card",
        };
    }

    /// Evaluate a hand with hole cards and board
    /// Used by clustering module for feature extraction
    pub fn evaluate(self: *const HandEvaluator, hole_cards: [2]Card, board: []const Card) HandRank {
        const total_cards = 2 + board.len;

        if (total_cards == 5) {
            // Exactly 5 cards - direct evaluation
            var cards: [5]Card = undefined;
            cards[0] = hole_cards[0];
            cards[1] = hole_cards[1];
            @memcpy(cards[2..], board);
            return self.evaluateFive(cards);
        } else if (total_cards == 6) {
            // 6 cards - check all combinations
            var cards: [6]Card = undefined;
            cards[0] = hole_cards[0];
            cards[1] = hole_cards[1];
            @memcpy(cards[2..], board);
            return self.evaluateSix(cards);
        } else if (total_cards == 7) {
            // 7 cards - check all combinations
            var cards: [7]Card = undefined;
            cards[0] = hole_cards[0];
            cards[1] = hole_cards[1];
            @memcpy(cards[2..], board);
            return self.evaluateSeven(cards);
        } else if (total_cards == 2) {
            // Preflop - return high card rank based on hole cards
            // This is a simplified evaluation for preflop
            const rank1 = CardOps.getRank(hole_cards[0]);
            const rank2 = CardOps.getRank(hole_cards[1]);
            const high_rank = @max(rank1, rank2);
            const low_rank = @min(rank1, rank2);

            // Simple preflop strength estimate
            if (rank1 == rank2) {
                // Pair - stronger than any high card
                const pair_strength = if (high_rank >= 12) 0 else @as(u16, @intCast(12 - high_rank)) * 10;
                return if (pair_strength > MAX_PAIR) MAX_PAIR else MAX_PAIR - pair_strength;
            } else {
                // High card - based on both cards
                const high_val = @as(u32, high_rank) * 100;
                const low_val = @as(u32, low_rank) * 10;
                const total_val = high_val + low_val;

                if (total_val >= MAX_HIGH_CARD) {
                    return MAX_HIGH_CARD;
                } else {
                    return MAX_HIGH_CARD - @as(HandRank, @intCast(total_val));
                }
            }
        } else {
            // Invalid number of cards
            return MAX_HIGH_CARD;
        }
    }
};

/// SIMD-optimized batch evaluator for high performance
pub const BatchEvaluator = struct {
    evaluator: HandEvaluator,

    pub fn init() BatchEvaluator {
        return BatchEvaluator{
            .evaluator = HandEvaluator.init(),
        };
    }

    /// Evaluate multiple 5-card hands simultaneously
    /// Input: slice of 5-card hands
    /// Output: slice of hand ranks (caller must provide buffer)
    pub fn evaluateFiveBatch(self: *const BatchEvaluator, hands: [][5]Card, results: []HandRank) void {
        std.debug.assert(hands.len == results.len);

        // For now, implement sequential version
        // TODO: Add SIMD vectorization using @Vector when requirements are clearer
        for (hands, results) |hand, *result| {
            result.* = self.evaluator.evaluateFive(hand);
        }
    }

    /// Evaluate multiple 7-card hands simultaneously
    pub fn evaluateSevenBatch(self: *const BatchEvaluator, hands: [][7]Card, results: []HandRank) void {
        std.debug.assert(hands.len == results.len);

        for (hands, results) |hand, *result| {
            result.* = self.evaluator.evaluateSeven(hand);
        }
    }
};

// Export compile-time constants for testing
pub const TEST_CARDS = struct {
    pub const ACE_SPADES = CardOps.fromString("As");
    pub const KING_SPADES = CardOps.fromString("Ks");
    pub const QUEEN_SPADES = CardOps.fromString("Qs");
    pub const JACK_SPADES = CardOps.fromString("Js");
    pub const TEN_SPADES = CardOps.fromString("Ts");
    pub const DEUCE_CLUBS = CardOps.fromString("2c");
    pub const TREY_DIAMONDS = CardOps.fromString("3d");
};

// Basic tests to ensure correctness
test "card creation and extraction" {
    const ace_spades = CardOps.fromString("As");

    // Test rank extraction (Ace = 12)
    try std.testing.expect(CardOps.getRank(ace_spades) == 12);

    // Test suit extraction (Spades = 1)
    try std.testing.expect(CardOps.getSuit(ace_spades) == SUIT_SPADES);

    // Test prime extraction (Ace prime = 41)
    try std.testing.expect(CardOps.getPrime(ace_spades) == 41);
}

test "hand evaluation basic" {
    var evaluator = HandEvaluator.init();

    // Royal flush in spades
    const royal_flush = [5]Card{
        TEST_CARDS.ACE_SPADES,
        TEST_CARDS.KING_SPADES,
        TEST_CARDS.QUEEN_SPADES,
        TEST_CARDS.JACK_SPADES,
        TEST_CARDS.TEN_SPADES,
    };

    const rank = evaluator.evaluateFive(royal_flush);

    // Royal flush should be rank 1 (best possible hand)
    try std.testing.expect(rank == 1);
    try std.testing.expect(HandEvaluator.getHandType(rank) == .straight_flush);
}

test "prime product calculation" {
    const cards = [3]Card{
        CardOps.fromString("As"), // Prime 41
        CardOps.fromString("Ks"), // Prime 37
        CardOps.fromString("Qs"), // Prime 31
    };

    const product = CardOps.primeProductFromHand(&cards);
    const expected = @as(u64, 41) * 37 * 31;

    try std.testing.expect(product == expected);
}
