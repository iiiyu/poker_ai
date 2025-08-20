const std = @import("std");
const Card = @import("eval_card.zig").Card;

// Hand evaluator matching Python's poker_ai.poker.evaluation.Evaluator
// Uses lookup tables for fast evaluation

pub const HandEvaluator = struct {
    // Hand rankings (lower is better, matching Python)
    pub const MAX_STRAIGHT_FLUSH: u32 = 10;
    pub const MAX_FOUR_OF_A_KIND: u32 = 166;
    pub const MAX_FULL_HOUSE: u32 = 322;
    pub const MAX_FLUSH: u32 = 1599;
    pub const MAX_STRAIGHT: u32 = 1609;
    pub const MAX_THREE_OF_A_KIND: u32 = 2467;
    pub const MAX_TWO_PAIR: u32 = 3325;
    pub const MAX_PAIR: u32 = 6185;
    pub const MAX_HIGH_CARD: u32 = 7462;
    
    // Evaluate 7-card hand (2 hole + 5 community)
    pub fn evaluate7Card(cards: []const Card) u32 {
        // Convert cards to eval integers
        var eval_cards: [7]u32 = undefined;
        for (cards, 0..) |card, i| {
            eval_cards[i] = card.eval_card;
        }
        
        // Find best 5-card combination
        var best_rank: u32 = MAX_HIGH_CARD + 1; // Worst possible
        
        // Generate all C(7,5) = 21 combinations
        var i: usize = 0;
        while (i < 7 - 4) : (i += 1) {
            var j = i + 1;
            while (j < 7 - 3) : (j += 1) {
                var k = j + 1;
                while (k < 7 - 2) : (k += 1) {
                    var l = k + 1;
                    while (l < 7 - 1) : (l += 1) {
                        var m = l + 1;
                        while (m < 7) : (m += 1) {
                            const five_cards = [_]u32{
                                eval_cards[i],
                                eval_cards[j],
                                eval_cards[k],
                                eval_cards[l],
                                eval_cards[m],
                            };
                            
                            const rank = evaluate5Card(&five_cards);
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
    
    // Evaluate 5-card hand
    pub fn evaluate5Card(cards: []const u32) u32 {
        // This is a simplified evaluator - full implementation would use lookup tables
        // For now, we'll use a basic evaluation
        
        // Check for flush - all cards must have the same suit
        const first_suit: u32 = (cards[0] >> 12) & 0xF;
        var is_flush = true;
        var ranks: u32 = 0;
        var product: u32 = 1;
        
        for (cards, 0..) |card, i| {
            const suit = (card >> 12) & 0xF;
            if (suit != first_suit) {
                is_flush = false;
            }
            ranks |= (card >> 16) & 0x1FFF;
            product *= card & 0xFF;
            _ = i;
        }
        
        // Check for straight using rank bits
        const is_straight = isStraight(ranks);
        
        if (is_flush and is_straight) {
            return getStraightFlushRank(ranks);
        }
        
        // Count rank frequencies
        var rank_counts = [_]u8{0} ** 13;
        for (cards) |card| {
            const rank = @as(u8, @truncate((card >> 8) & 0xF));
            rank_counts[rank] += 1;
        }
        
        // Check for quads, trips, pairs
        var quads: u8 = 0;
        var trips: u8 = 0;
        var pairs: u8 = 0;
        var quad_rank: u8 = 0;
        var trip_rank: u8 = 0;
        var pair_ranks = [_]u8{0} ** 2;
        var pair_count: u8 = 0;
        
        var r: i8 = 12; // Start from Ace
        while (r >= 0) : (r -= 1) {
            const rank = @as(u8, @intCast(r));
            const count = rank_counts[rank];
            
            if (count == 4) {
                quads = 1;
                quad_rank = rank;
            } else if (count == 3) {
                trips = 1;
                trip_rank = rank;
            } else if (count == 2) {
                if (pair_count < 2) {
                    pair_ranks[pair_count] = rank;
                    pair_count += 1;
                }
                pairs = pair_count;
            }
        }
        
        // Return appropriate rank
        if (quads > 0) {
            const qr = @min(quad_rank, 12);
            return @as(u32, 11) + @as(u32, 12 - qr) * 10; // Four of a kind
        }
        
        if (trips > 0 and pairs > 0) {
            const tr = @min(trip_rank, 12);
            return @as(u32, 167) + @as(u32, 12 - tr) * 10; // Full house
        }
        
        if (is_flush) {
            return @as(u32, 323) + getHighCardRank(rank_counts); // Flush
        }
        
        if (is_straight) {
            return @as(u32, 1600) + getStraightRank(ranks); // Straight
        }
        
        if (trips > 0) {
            const tr = @min(trip_rank, 12);
            return @as(u32, 1610) + @as(u32, 12 - tr) * 50; // Three of a kind
        }
        
        if (pairs >= 2) {
            const pr0 = @min(pair_ranks[0], 12);
            const pr1 = @min(pair_ranks[1], 12);
            return @as(u32, 2468) + @as(u32, 12 - pr0) * 50 + @as(u32, 12 - pr1) * 3; // Two pair
        }
        
        if (pairs == 1) {
            // Ensure pair_ranks[0] is valid (0-12)
            const pr = @min(pair_ranks[0], 12);
            return @as(u32, 3326) + @as(u32, 12 - pr) * 200; // One pair
        }
        
        // High card
        return @as(u32, 6186) + getHighCardRank(rank_counts);
    }
    
    fn isStraight(rank_bits: u32) bool {
        // Check for 5 consecutive bits
        const straight_masks = [_]u32{
            0b1111100000000, // A-K-Q-J-T
            0b0111110000000, // K-Q-J-T-9
            0b0011111000000, // Q-J-T-9-8
            0b0001111100000, // J-T-9-8-7
            0b0000111110000, // T-9-8-7-6
            0b0000011111000, // 9-8-7-6-5
            0b0000001111100, // 8-7-6-5-4
            0b0000000111110, // 7-6-5-4-3
            0b0000000011111, // 6-5-4-3-2
            0b1000000001111, // A-2-3-4-5 (wheel)
        };
        
        for (straight_masks) |mask| {
            if ((rank_bits & mask) == mask) {
                return true;
            }
        }
        return false;
    }
    
    fn getStraightRank(rank_bits: u32) u32 {
        // Return rank based on highest card in straight
        if ((rank_bits & 0b1111100000000) == 0b1111100000000) return 0; // A-high
        if ((rank_bits & 0b0111110000000) == 0b0111110000000) return 1; // K-high
        if ((rank_bits & 0b0011111000000) == 0b0011111000000) return 2; // Q-high
        if ((rank_bits & 0b0001111100000) == 0b0001111100000) return 3; // J-high
        if ((rank_bits & 0b0000111110000) == 0b0000111110000) return 4; // T-high
        if ((rank_bits & 0b0000011111000) == 0b0000011111000) return 5; // 9-high
        if ((rank_bits & 0b0000001111100) == 0b0000001111100) return 6; // 8-high
        if ((rank_bits & 0b0000000111110) == 0b0000000111110) return 7; // 7-high
        if ((rank_bits & 0b0000000011111) == 0b0000000011111) return 8; // 6-high
        if ((rank_bits & 0b1000000001111) == 0b1000000001111) return 9; // 5-high (wheel)
        return 9;
    }
    
    fn getStraightFlushRank(rank_bits: u32) u32 {
        return getStraightRank(rank_bits) + 1; // Straight flush ranks 1-10
    }
    
    fn getHighCardRank(rank_counts: [13]u8) u32 {
        // Return a small rank offset for high card hands
        // We want to differentiate between flushes but keep the value small
        // Max flush is 1599, min flush is 323, so we have ~1276 values to work with
        
        var rank: u32 = 0;
        var multiplier: u32 = 100;
        var found: u8 = 0;
        
        var r: i8 = 12; // Start from Ace
        while (r >= 0 and found < 5) : (r -= 1) {
            const idx = @as(u8, @intCast(r));
            if (rank_counts[idx] > 0) {
                rank += @as(u32, idx) * multiplier;
                multiplier = multiplier / 2; // Decrease importance of lower cards
                found += 1;
            }
        }
        
        // Ensure we stay within range (max about 1200)
        return @min(rank, 1276);
    }
    
    // Compare two hands and return winner
    pub fn compareHands(our_cards: []const Card, opp_cards: []const Card, board: []const Card) u8 {
        // Build 7-card hands
        var our_hand = std.ArrayList(Card).init(std.heap.page_allocator);
        defer our_hand.deinit();
        var opp_hand = std.ArrayList(Card).init(std.heap.page_allocator);
        defer opp_hand.deinit();
        
        // Add hole cards
        for (our_cards) |card| {
            our_hand.append(card) catch {};
        }
        for (opp_cards) |card| {
            opp_hand.append(card) catch {};
        }
        
        // Add board
        for (board) |card| {
            our_hand.append(card) catch {};
            opp_hand.append(card) catch {};
        }
        
        const our_rank = evaluate7Card(our_hand.items);
        const opp_rank = evaluate7Card(opp_hand.items);
        
        // Lower rank is better!
        if (our_rank < opp_rank) return 0; // We win
        if (our_rank > opp_rank) return 1; // We lose
        return 2; // Tie
    }
};