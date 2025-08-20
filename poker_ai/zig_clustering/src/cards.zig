const std = @import("std");
const testing = std.testing;

// Suit constants matching Python's order
pub const SUIT_SPADES: u8 = 1;   // "spades" in Python
pub const SUIT_DIAMONDS: u8 = 2; // "diamonds" in Python  
pub const SUIT_CLUBS: u8 = 3;    // "clubs" in Python
pub const SUIT_HEARTS: u8 = 4;   // "hearts" in Python

// Card representation - matches Python's [rank, suit] format
pub const Card = struct {
    rank: u8, // 2-14 (14 = Ace)
    suit: u8, // 1-4 (see suit constants above)

    pub fn init(rank: u8, suit: u8) Card {
        return Card{ .rank = rank, .suit = suit };
    }

    pub fn eql(self: Card, other: Card) bool {
        return self.rank == other.rank and self.suit == other.suit;
    }

    pub fn toInt(self: Card) u32 {
        // Convert to single integer for efficient storage
        return (@as(u32, self.rank) << 8) | @as(u32, self.suit);
    }

    pub fn fromInt(value: u32) Card {
        return Card{
            .rank = @truncate(value >> 8),
            .suit = @truncate(value & 0xFF),
        };
    }
};

// Combo types matching Python's structure
pub const HandCombo = [2]Card;
pub const FlopCombo = [5]Card; // 2 hand + 3 flop
pub const TurnCombo = [6]Card; // 2 hand + 3 flop + 1 turn
pub const RiverCombo = [7]Card; // 2 hand + 3 flop + 1 turn + 1 river

pub const CardCombos = struct {
    allocator: std.mem.Allocator,
    low_rank: u8,
    high_rank: u8,
    all_cards: []Card,
    river_combos: []RiverCombo,
    turn_combos: []TurnCombo,
    flop_combos: []FlopCombo,

    pub fn init(allocator: std.mem.Allocator, low_rank: u8, high_rank: u8) !CardCombos {
        var self = CardCombos{
            .allocator = allocator,
            .low_rank = low_rank,
            .high_rank = high_rank,
            .all_cards = undefined,
            .river_combos = undefined,
            .turn_combos = undefined,
            .flop_combos = undefined,
        };

        // Generate all cards (suit-first ordering to match Python)
        const n_ranks = high_rank - low_rank + 1;
        const n_cards = n_ranks * 4;
        self.all_cards = try allocator.alloc(Card, n_cards);

        var idx: usize = 0;
        // IMPORTANT: Suit-first ordering to match Python
        // Python order: all spades, then diamonds, then clubs, then hearts
        var suit: u8 = 1;
        while (suit <= 4) : (suit += 1) {
            var rank: u8 = low_rank;
            while (rank <= high_rank) : (rank += 1) {
                self.all_cards[idx] = Card.init(rank, suit);
                idx += 1;
            }
        }

        // Generate combinations
        try self.generateCombinations();

        return self;
    }

    pub fn deinit(self: *CardCombos) void {
        self.allocator.free(self.all_cards);
        self.allocator.free(self.river_combos);
        self.allocator.free(self.turn_combos);
        self.allocator.free(self.flop_combos);
    }

    fn generateCombinations(self: *CardCombos) !void {
        // For testing/small decks, generate limited combos
        // In production, this would generate all valid combinations
        
        // Calculate combination counts (simplified for memory efficiency)
        _ = self.all_cards.len; // Will be used in production
        
        // For a full deck: C(52,2) * C(50,3) * 47 * 46 ≈ 133M river combos
        // We'll use streaming generation in practice
        
        // For now, allocate space for a subset
        const max_samples = 1000; // Limit for testing
        
        // River combinations: hand(2) + board(5)
        var river_list = std.ArrayList(RiverCombo).init(self.allocator);
        defer river_list.deinit();
        
        var count: usize = 0;
        for (self.all_cards, 0..) |card1, i| {
            for (self.all_cards[i+1..], i+1..) |card2, j| {
                if (count >= max_samples) break;
                
                // Sample some board cards
                for (self.all_cards, 0..) |card3, k| {
                    if (k == i or k == j) continue;
                    for (self.all_cards[k+1..], k+1..) |card4, l| {
                        if (l == i or l == j) continue;
                        for (self.all_cards[l+1..], l+1..) |card5, m| {
                            if (m == i or m == j) continue;
                            for (self.all_cards[m+1..], m+1..) |card6, n| {
                                if (n == i or n == j) continue;
                                for (self.all_cards[n+1..], n+1..) |card7, o| {
                                    if (o == i or o == j) continue;
                                    if (count >= max_samples) break;
                                    
                                    const combo = RiverCombo{
                                        card1, card2, // hand
                                        card3, card4, card5, // flop
                                        card6, // turn
                                        card7, // river
                                    };
                                    try river_list.append(combo);
                                    count += 1;
                                }
                                if (count >= max_samples) break;
                            }
                            if (count >= max_samples) break;
                        }
                        if (count >= max_samples) break;
                    }
                    if (count >= max_samples) break;
                }
                if (count >= max_samples) break;
            }
            if (count >= max_samples) break;
        }
        
        self.river_combos = try river_list.toOwnedSlice();
        
        // Similar for turn and flop (simplified)
        self.turn_combos = try self.allocator.alloc(TurnCombo, @min(max_samples, 13860));
        self.flop_combos = try self.allocator.alloc(FlopCombo, @min(max_samples, 7920));
        
        // Fill with sample combinations
        for (self.turn_combos, 0..) |*combo, idx| {
            if (idx < self.all_cards.len - 5) {
                combo[0] = self.all_cards[0];
                combo[1] = self.all_cards[1];
                combo[2] = self.all_cards[2];
                combo[3] = self.all_cards[3];
                combo[4] = self.all_cards[4];
                combo[5] = self.all_cards[@min(5 + idx, self.all_cards.len - 1)];
            }
        }
        
        for (self.flop_combos, 0..) |*combo, idx| {
            if (idx < self.all_cards.len - 4) {
                combo[0] = self.all_cards[0];
                combo[1] = self.all_cards[1];
                combo[2] = self.all_cards[2];
                combo[3] = self.all_cards[3];
                combo[4] = self.all_cards[@min(4 + idx, self.all_cards.len - 1)];
            }
        }
    }

    // Stream combinations for memory efficiency
    pub fn streamRiverCombos(self: *CardCombos, callback: fn(combo: RiverCombo) void) !void {
        // In production, this would generate combinations on-the-fly
        // without storing them all in memory
        for (self.river_combos) |combo| {
            callback(combo);
        }
    }
};

// Utility functions
pub fn getAvailableCards(allocator: std.mem.Allocator, all_cards: []const Card, unavailable: []const Card) ![]Card {
    var available = std.ArrayList(Card).init(allocator);
    defer available.deinit();

    for (all_cards) |card| {
        var is_available = true;
        for (unavailable) |unavail| {
            if (card.eql(unavail)) {
                is_available = false;
                break;
            }
        }
        if (is_available) {
            try available.append(card);
        }
    }

    return available.toOwnedSlice();
}

test "Card initialization and equality" {
    const card1 = Card.init(14, 1); // Ace of suit 1
    const card2 = Card.init(14, 1);
    const card3 = Card.init(2, 1);

    try testing.expect(card1.eql(card2));
    try testing.expect(!card1.eql(card3));
}

test "Card to/from integer conversion" {
    const card = Card.init(14, 3);
    const int_val = card.toInt();
    const restored = Card.fromInt(int_val);
    
    try testing.expect(card.eql(restored));
}

test "CardCombos initialization" {
    const allocator = testing.allocator;
    var combos = try CardCombos.init(allocator, 2, 4); // Small deck for testing
    defer combos.deinit();

    try testing.expect(combos.all_cards.len == 12); // 3 ranks * 4 suits
}