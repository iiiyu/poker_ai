const std = @import("std");
const Card = @import("cards.zig").Card;

// Poker hand rankings (lower is better, matching Python)
pub const HandRank = enum(u32) {
    STRAIGHT_FLUSH = 1,    // 1-10
    FOUR_OF_A_KIND = 11,   // 11-166
    FULL_HOUSE = 167,      // 167-322
    FLUSH = 323,           // 323-1599
    STRAIGHT = 1600,       // 1600-1609
    THREE_OF_A_KIND = 1610, // 1610-2467
    TWO_PAIR = 2468,       // 2468-3325
    ONE_PAIR = 3326,       // 3326-6185
    HIGH_CARD = 6186,      // 6186-7462
};

pub const PokerEvaluator = struct {
    // Evaluate a 7-card hand (2 hole + 5 board)
    pub fn evaluate7Card(cards: []const Card) u32 {
        // Find best 5-card combination from 7 cards
        var best_rank: u32 = 9999999; // Worst possible
        
        // Generate all 5-card combinations (C(7,5) = 21)
        var combo: [5]Card = undefined;
        var i: usize = 0;
        while (i < cards.len - 4) : (i += 1) {
            var j = i + 1;
            while (j < cards.len - 3) : (j += 1) {
                var k = j + 1;
                while (k < cards.len - 2) : (k += 1) {
                    var l = k + 1;
                    while (l < cards.len - 1) : (l += 1) {
                        var m = l + 1;
                        while (m < cards.len) : (m += 1) {
                            combo[0] = cards[i];
                            combo[1] = cards[j];
                            combo[2] = cards[k];
                            combo[3] = cards[l];
                            combo[4] = cards[m];
                            
                            const rank = evaluate5Card(&combo);
                            if (rank < best_rank) {
                                best_rank = rank;
                            }
                        }
                    }
                }
            }
        }
        
        return best_rank;
    }
    
    // Evaluate a 5-card hand
    pub fn evaluate5Card(cards: *const [5]Card) u32 {
        // Count ranks and suits
        var rank_counts = [_]u8{0} ** 15; // 2-14 (Ace)
        var suit_counts = [_]u8{0} ** 5;  // 1-4
        
        for (cards) |card| {
            rank_counts[card.rank] += 1;
            suit_counts[card.suit] += 1;
        }
        
        // Check for flush
        var is_flush = false;
        for (suit_counts[1..]) |count| {
            if (count >= 5) {
                is_flush = true;
                break;
            }
        }
        
        // Check for straight
        var is_straight = false;
        var straight_high: u8 = 0;
        
        // Check A-2-3-4-5 (wheel)
        if (rank_counts[14] > 0 and rank_counts[2] > 0 and 
            rank_counts[3] > 0 and rank_counts[4] > 0 and rank_counts[5] > 0) {
            is_straight = true;
            straight_high = 5;
        }
        
        // Check regular straights
        if (!is_straight) {
            var consecutive: u8 = 0;
            var r: u8 = 2;
            while (r <= 14) : (r += 1) {
                if (rank_counts[r] > 0) {
                    consecutive += 1;
                    if (consecutive >= 5) {
                        is_straight = true;
                        straight_high = r;
                    }
                } else {
                    consecutive = 0;
                }
            }
        }
        
        // Count pairs, trips, quads
        var pairs: u8 = 0;
        var trips: u8 = 0;
        var quads: u8 = 0;
        var pair_ranks = [_]u8{0} ** 2;
        var trip_rank: u8 = 0;
        var quad_rank: u8 = 0;
        
        var r: u8 = 14; // Start from Ace (highest)
        while (r >= 2) : (r -= 1) {
            const count = rank_counts[r];
            if (count == 4) {
                quads += 1;
                quad_rank = r;
            } else if (count == 3) {
                trips += 1;
                trip_rank = r;
            } else if (count == 2) {
                if (pairs < 2) {
                    pair_ranks[pairs] = r;
                }
                pairs += 1;
            }
        }
        
        // Determine hand ranking
        if (is_straight and is_flush) {
            // Straight flush
            return @intFromEnum(HandRank.STRAIGHT_FLUSH) + @as(u32, 14 - straight_high);
        }
        
        if (quads > 0) {
            // Four of a kind
            return @intFromEnum(HandRank.FOUR_OF_A_KIND) + @as(u32, 14 - quad_rank) * 13 + getKicker(cards, rank_counts, quad_rank, 4);
        }
        
        if (trips > 0 and pairs > 0) {
            // Full house
            return @intFromEnum(HandRank.FULL_HOUSE) + @as(u32, 14 - trip_rank) * 13 + @as(u32, 14 - pair_ranks[0]);
        }
        
        if (is_flush) {
            // Flush
            return @intFromEnum(HandRank.FLUSH) + getHighCardValue(cards, rank_counts);
        }
        
        if (is_straight) {
            // Straight
            return @intFromEnum(HandRank.STRAIGHT) + @as(u32, 14 - straight_high);
        }
        
        if (trips > 0) {
            // Three of a kind
            return @intFromEnum(HandRank.THREE_OF_A_KIND) + @as(u32, 14 - trip_rank) * 169 + getKickers(cards, rank_counts, trip_rank, 3, 2);
        }
        
        if (pairs >= 2) {
            // Two pair
            const high_pair = pair_ranks[0];
            const low_pair = pair_ranks[1];
            return @intFromEnum(HandRank.TWO_PAIR) + @as(u32, 14 - high_pair) * 169 + @as(u32, 14 - low_pair) * 13 + getKicker(cards, rank_counts, high_pair, 2);
        }
        
        if (pairs == 1) {
            // One pair
            return @intFromEnum(HandRank.ONE_PAIR) + @as(u32, 14 - pair_ranks[0]) * 2197 + getKickers(cards, rank_counts, pair_ranks[0], 2, 3);
        }
        
        // High card
        return @intFromEnum(HandRank.HIGH_CARD) + getHighCardValue(cards, rank_counts);
    }
    
    // Get kicker value (for breaking ties)
    fn getKicker(cards: *const [5]Card, rank_counts: [15]u8, exclude_rank: u8, exclude_count: u8) u32 {
        _ = cards;
        _ = exclude_count;
        var r: u8 = 14;
        while (r >= 2) : (r -= 1) {
            if (r != exclude_rank and rank_counts[r] > 0) {
                return @as(u32, 14 - r);
            }
        }
        return 0;
    }
    
    // Get multiple kickers
    fn getKickers(cards: *const [5]Card, rank_counts: [15]u8, exclude_rank: u8, exclude_count: u8, num_kickers: u8) u32 {
        _ = cards;
        _ = exclude_count;
        var value: u32 = 0;
        var found: u8 = 0;
        var multiplier: u32 = 1;
        
        var r: u8 = 14;
        while (r >= 2 and found < num_kickers) : (r -= 1) {
            if (r != exclude_rank and rank_counts[r] > 0) {
                value += @as(u32, 14 - r) * multiplier;
                multiplier *= 13;
                found += 1;
            }
        }
        return value;
    }
    
    // Get high card value for high card and flush hands
    fn getHighCardValue(cards: *const [5]Card, rank_counts: [15]u8) u32 {
        _ = cards;
        var value: u32 = 0;
        var multiplier: u32 = 1;
        var found: u8 = 0;
        
        var r: u8 = 14;
        while (r >= 2 and found < 5) : (r -= 1) {
            if (rank_counts[r] > 0) {
                value += @as(u32, 14 - r) * multiplier;
                multiplier *= 13;
                found += 1;
            }
        }
        return value;
    }
    
    // Compare two hands (returns 0 for win, 1 for loss, 2 for tie)
    pub fn compareHands(our_cards: []const Card, opp_cards: []const Card, board: []const Card) u8 {
        // Create 7-card hands
        var our_hand: [7]Card = undefined;
        var opp_hand: [7]Card = undefined;
        
        // Copy hole cards
        our_hand[0] = our_cards[0];
        our_hand[1] = our_cards[1];
        opp_hand[0] = opp_cards[0];
        opp_hand[1] = opp_cards[1];
        
        // Copy board
        for (board, 2..) |card, i| {
            our_hand[i] = card;
            opp_hand[i] = card;
        }
        
        const our_rank = evaluate7Card(&our_hand);
        const opp_rank = evaluate7Card(&opp_hand);
        
        // IMPORTANT: Lower rank is better!
        if (our_rank < opp_rank) return 0; // We win
        if (our_rank > opp_rank) return 1; // We lose
        return 2; // Tie
    }
};

// Tests
test "Poker evaluator - Pair beats high card" {
    const allocator = std.testing.allocator;
    _ = allocator;
    
    // Pair of aces
    const pair_hand = [_]Card{
        Card.init(14, 1), Card.init(14, 2), // AA
        Card.init(2, 1), Card.init(3, 2), Card.init(5, 3),
    };
    
    // High card ace
    const high_hand = [_]Card{
        Card.init(14, 1), Card.init(10, 2), // AK
        Card.init(2, 1), Card.init(3, 2), Card.init(5, 3),
    };
    
    const pair_rank = PokerEvaluator.evaluate5Card(&pair_hand);
    const high_rank = PokerEvaluator.evaluate5Card(&high_hand);
    
    // Pair should have lower rank (better hand)
    try std.testing.expect(pair_rank < high_rank);
}

test "Poker evaluator - Flush beats pair" {
    // Flush
    const flush_hand = [_]Card{
        Card.init(2, 1), Card.init(5, 1), Card.init(7, 1),
        Card.init(9, 1), Card.init(10, 1), // All suit 1
    };
    
    // Pair of aces
    const pair_hand = [_]Card{
        Card.init(14, 1), Card.init(14, 2), // AA
        Card.init(2, 3), Card.init(3, 4), Card.init(5, 1),
    };
    
    const flush_rank = PokerEvaluator.evaluate5Card(&flush_hand);
    const pair_rank = PokerEvaluator.evaluate5Card(&pair_hand);
    
    // Flush should have lower rank (better hand)
    try std.testing.expect(flush_rank < pair_rank);
}

test "Poker evaluator - Straight detection" {
    // Straight: 5-6-7-8-9
    const straight_hand = [_]Card{
        Card.init(5, 1), Card.init(6, 2), Card.init(7, 3),
        Card.init(8, 4), Card.init(9, 1),
    };
    
    const rank = PokerEvaluator.evaluate5Card(&straight_hand);
    
    // Should be in straight range
    try std.testing.expect(rank >= @intFromEnum(HandRank.STRAIGHT));
    try std.testing.expect(rank < @intFromEnum(HandRank.THREE_OF_A_KIND));
}

test "Poker evaluator - Full house detection" {
    // Full house: AAA + 22
    const full_house = [_]Card{
        Card.init(14, 1), Card.init(14, 2), Card.init(14, 3), // Three aces
        Card.init(2, 1), Card.init(2, 2), // Pair of 2s
    };
    
    const rank = PokerEvaluator.evaluate5Card(&full_house);
    
    // Should be in full house range
    try std.testing.expect(rank >= @intFromEnum(HandRank.FULL_HOUSE));
    try std.testing.expect(rank < @intFromEnum(HandRank.FLUSH));
}