const std = @import("std");

// Basic hand evaluator without lookup tables for testing
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
        comptime {
            if (str.len != 2) @compileError("Card string must be exactly 2 characters");
            
            const rank_char = str[0];
            const suit_char = str[1];
            
            // Convert rank character to rank integer
            const rank_int = blk: {
                for (STR_RANKS, 0..) |r, i| {
                    if (r == rank_char) break :blk @as(u32, @intCast(i));
                }
                @compileError("Invalid rank character: " ++ [1]u8{rank_char});
            };
            
            // Convert suit character to suit integer
            const suit_int = switch (suit_char) {
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
};

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
    const ace_spades = comptime CardOps.fromString("As");
    
    // Test rank extraction (Ace = 12)
    try std.testing.expect(CardOps.getRank(ace_spades) == 12);
    
    // Test suit extraction (Spades = 1)
    try std.testing.expect(CardOps.getSuit(ace_spades) == SUIT_SPADES);
    
    // Test prime extraction (Ace prime = 41)
    try std.testing.expect(CardOps.getPrime(ace_spades) == 41);
}

test "runtime card creation" {
    const ace_spades = try CardOps.fromStringRuntime("As");
    const comptime_ace = comptime CardOps.fromString("As");
    
    // Should match compile-time version
    try std.testing.expect(ace_spades == comptime_ace);
}

test "prime product calculation" {
    const cards = [3]Card{
        comptime CardOps.fromString("As"), // Prime 41
        comptime CardOps.fromString("Ks"), // Prime 37  
        comptime CardOps.fromString("Qs"), // Prime 31
    };
    
    const product = CardOps.primeProductFromHand(&cards);
    const expected = @as(u64, 41) * 37 * 31;
    
    try std.testing.expect(product == expected);
}

test "hand type classification" {
    try std.testing.expect(getHandType(1) == .straight_flush);
    try std.testing.expect(getHandType(MAX_STRAIGHT_FLUSH) == .straight_flush);
    try std.testing.expect(getHandType(MAX_STRAIGHT_FLUSH + 1) == .four_of_a_kind);
    try std.testing.expect(getHandType(MAX_HIGH_CARD) == .high_card);
}

test "card bit representation validation" {
    // Test that our cards have the same bit representation as Python
    const ace_spades = comptime CardOps.fromString("As");
    
    // From Python: Ace of spades = 0x10001C29 = 268442665
    // Let's verify the components are correct
    try std.testing.expect(CardOps.getRank(ace_spades) == 12);
    try std.testing.expect(CardOps.getSuit(ace_spades) == 1);
    try std.testing.expect(CardOps.getPrime(ace_spades) == 41);
    
    // The full card value should match Python's calculation
    std.debug.print("Ace of spades: 0x{X:0>8} ({})\n", .{ ace_spades, ace_spades });
}

test "python compatibility - card values" {
    // Test specific card values from Python validation
    const test_cards = [_]struct {
        str: []const u8,
        expected_rank: u8,
        expected_suit: u8,
        expected_prime: u8,
    }{
        .{ .str = "As", .expected_rank = 12, .expected_suit = 1, .expected_prime = 41 },
        .{ .str = "Ks", .expected_rank = 11, .expected_suit = 1, .expected_prime = 37 },
        .{ .str = "Qs", .expected_rank = 10, .expected_suit = 1, .expected_prime = 31 },
        .{ .str = "2c", .expected_rank = 0, .expected_suit = 8, .expected_prime = 2 },
        .{ .str = "7h", .expected_rank = 5, .expected_suit = 2, .expected_prime = 13 },
        .{ .str = "9d", .expected_rank = 7, .expected_suit = 4, .expected_prime = 19 },
    };
    
    for (test_cards) |test_card| {
        const card = try CardOps.fromStringRuntime(test_card.str);
        try std.testing.expect(CardOps.getRank(card) == test_card.expected_rank);
        try std.testing.expect(CardOps.getSuit(card) == test_card.expected_suit);
        try std.testing.expect(CardOps.getPrime(card) == test_card.expected_prime);
    }
}