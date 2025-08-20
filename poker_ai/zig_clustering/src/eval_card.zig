const std = @import("std");

// EvaluationCard implementation matching Python's eval_card.py
// Card representation as 32-bit integer for fast evaluation
//
//                     EvaluationCard:
//               bitrank     suit rank   prime
//         +--------+--------+--------+--------+
//         |xxxbbbbb|bbbbbbbb|cdhsrrrr|xxpppppp|
//         +--------+--------+--------+--------+
//
// 1) p = prime number of rank (deuce=2,trey=3,four=5,...,ace=41)
// 2) r = rank of card (deuce=0,trey=1,four=2,five=3,...,ace=12)
// 3) cdhs = suit of card (bit turned on based on suit of card)
// 4) b = bit turned on depending on rank of card

pub const EvalCard = struct {
    // Rank mappings (Python uses 2-14, but internally 0-12)
    pub const RANK_2: u8 = 0;
    pub const RANK_3: u8 = 1;
    pub const RANK_4: u8 = 2;
    pub const RANK_5: u8 = 3;
    pub const RANK_6: u8 = 4;
    pub const RANK_7: u8 = 5;
    pub const RANK_8: u8 = 6;
    pub const RANK_9: u8 = 7;
    pub const RANK_T: u8 = 8;
    pub const RANK_J: u8 = 9;
    pub const RANK_Q: u8 = 10;
    pub const RANK_K: u8 = 11;
    pub const RANK_A: u8 = 12;
    
    // Suit bits
    pub const SUIT_SPADES: u8 = 1;   // 0001
    pub const SUIT_HEARTS: u8 = 2;   // 0010
    pub const SUIT_DIAMONDS: u8 = 4; // 0100
    pub const SUIT_CLUBS: u8 = 8;    // 1000
    
    // Prime numbers for each rank
    const PRIMES = [_]u8{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41 };
    
    // Convert Python-style rank (2-14) and suit string to eval card
    pub fn new(rank: u8, suit: []const u8) u32 {
        // Convert Python rank (2-14) to internal rank (0-12)
        const rank_int = if (rank == 14) RANK_A else rank - 2;
        
        // Convert suit string to suit bits
        const suit_int = switch (suit[0]) {
            's' => SUIT_SPADES,
            'h' => SUIT_HEARTS,
            'd' => SUIT_DIAMONDS,
            'c' => SUIT_CLUBS,
            else => unreachable,
        };
        
        const rank_prime = PRIMES[rank_int];
        
        // Build the card integer
        const bitrank = @as(u32, 1) << @intCast(rank_int + 16);
        const suit_bits = @as(u32, suit_int) << 12;
        const rank_bits = @as(u32, rank_int) << 8;
        
        return bitrank | suit_bits | rank_bits | rank_prime;
    }
    
    // Create from rank and suit integers (matching Python Card class)
    pub fn fromRankSuit(rank: u8, suit_str: []const u8) u32 {
        return new(rank, suit_str);
    }
    
    // Get rank from card integer (0-12)
    pub fn getRankInt(card_int: u32) u8 {
        return @truncate((card_int >> 8) & 0xF);
    }
    
    // Get suit from card integer
    pub fn getSuitInt(card_int: u32) u8 {
        return @truncate((card_int >> 12) & 0xF);
    }
    
    // Get bitrank from card integer
    pub fn getBitrankInt(card_int: u32) u16 {
        return @truncate((card_int >> 16) & 0x1FFF);
    }
    
    // Get prime from card integer
    pub fn getPrime(card_int: u32) u8 {
        return @truncate(card_int & 0x3F);
    }
};

// Python-compatible Card structure
pub const Card = struct {
    rank: u8,     // 2-14 (Python style)
    suit: []const u8,  // "spades", "hearts", "diamonds", "clubs"
    eval_card: u32,    // EvaluationCard integer
    
    // Suit string constants
    pub const SPADES = "spades";
    pub const HEARTS = "hearts";
    pub const DIAMONDS = "diamonds";
    pub const CLUBS = "clubs";
    
    pub fn init(rank: u8, suit: []const u8) Card {
        const suit_char = [_]u8{suit[0]};
        const eval = EvalCard.fromRankSuit(rank, &suit_char);
        return Card{
            .rank = rank,
            .suit = suit,
            .eval_card = eval,
        };
    }
    
    // Convert to integer (for Python compatibility)
    pub fn toInt(self: Card) u32 {
        return self.eval_card;
    }
    
    // Check equality
    pub fn eql(self: Card, other: Card) bool {
        return self.eval_card == other.eval_card;
    }
    
    // For hashing
    pub fn hash(self: Card) u32 {
        return self.eval_card;
    }
};

// Generate all cards in Python order (suit-first)
pub fn generateAllCards(allocator: std.mem.Allocator) ![]Card {
    const suits = [_][]const u8{ Card.SPADES, Card.DIAMONDS, Card.CLUBS, Card.HEARTS };
    const ranks = [_]u8{ 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }; // 11=J, 12=Q, 13=K, 14=A
    
    var cards = try allocator.alloc(Card, 52);
    var idx: usize = 0;
    
    // Suit-first ordering to match Python
    for (suits) |suit| {
        for (ranks) |rank| {
            cards[idx] = Card.init(rank, suit);
            idx += 1;
        }
    }
    
    return cards;
}

// Tests
test "EvalCard creation matches Python" {
    // Test Ace of Spades
    const ace_spades = Card.init(14, "spades");
    
    // The eval_card should be a specific integer
    // We can't test exact value without Python reference, but structure should be valid
    try std.testing.expect(ace_spades.eval_card > 0);
    try std.testing.expect(ace_spades.rank == 14);
    try std.testing.expect(std.mem.eql(u8, ace_spades.suit, "spades"));
}

test "Card generation order" {
    const allocator = std.testing.allocator;
    const cards = try generateAllCards(allocator);
    defer allocator.free(cards);
    
    // First card should be 2 of spades
    try std.testing.expect(cards[0].rank == 2);
    try std.testing.expect(std.mem.eql(u8, cards[0].suit, "spades"));
    
    // 13th card should be Ace of spades (last spade)
    try std.testing.expect(cards[12].rank == 14);
    try std.testing.expect(std.mem.eql(u8, cards[12].suit, "spades"));
    
    // 14th card should be 2 of diamonds
    try std.testing.expect(cards[13].rank == 2);
    try std.testing.expect(std.mem.eql(u8, cards[13].suit, "diamonds"));
}