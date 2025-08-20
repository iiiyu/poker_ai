const std = @import("std");
const Card = @import("eval_card.zig").Card;
const HandEvaluator = @import("evaluator.zig").HandEvaluator;

// Equity Calculator for Expected Hand Strength (EHS)
pub const EquityCalculator = struct {
    allocator: std.mem.Allocator,
    evaluator: HandEvaluator,
    
    pub fn init(allocator: std.mem.Allocator) EquityCalculator {
        return EquityCalculator{
            .allocator = allocator,
            .evaluator = HandEvaluator{},
        };
    }
    
    // Calculate Expected Hand Strength
    // EHS = P(win) + 0.5 * P(tie)
    pub fn calculateEHS(
        self: *EquityCalculator,
        our_hand: []const Card,  // 2 cards
        board: []const Card,      // 3-5 cards
        all_cards: []const Card,  // All 52 cards
        n_simulations: u32,
        seed: u64,
    ) !f32 {
        // Get available cards for opponent
        const available = try self.getAvailableCards(our_hand, board, all_cards);
        defer self.allocator.free(available);
        
        if (available.len < 2) return 0.5; // Not enough cards
        
        var wins: f32 = 0;
        var total: u32 = 0;
        
        // Random number generator
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        
        // Monte Carlo simulation
        var sim: u32 = 0;
        while (sim < n_simulations) : (sim += 1) {
            // Sample opponent hand (2 cards)
            const idx1 = random.intRangeLessThan(usize, 0, available.len);
            var idx2 = random.intRangeLessThan(usize, 0, available.len);
            while (idx2 == idx1) {
                idx2 = random.intRangeLessThan(usize, 0, available.len);
            }
            
            const opp_hand = [_]Card{ available[idx1], available[idx2] };
            
            // Compare hands
            const result = HandEvaluator.compareHands(our_hand, &opp_hand, board);
            
            if (result == 0) {
                wins += 1.0; // We win
            } else if (result == 2) {
                wins += 0.5; // Tie
            }
            
            total += 1;
        }
        
        return if (total > 0) wins / @as(f32, @floatFromInt(total)) else 0.5;
    }
    
    // Calculate EHS distribution over possible next cards
    pub fn calculateDistribution(
        self: *EquityCalculator,
        our_hand: []const Card,
        board: []const Card,
        all_cards: []const Card,
        n_next_cards: usize,    // How many cards to add (1 for turn->river, 2 for flop->river)
        n_clusters: usize,      // Number of clusters to distribute over
        cluster_map: ?std.AutoHashMap(u64, u32), // Map from combo hash to cluster ID
        n_simulations: u32,
        seed: u64,
    ) ![]f32 {
        // Initialize distribution
        var distribution = try self.allocator.alloc(f32, n_clusters);
        @memset(distribution, 0);
        
        // Get available cards for next street
        const available = try self.getAvailableCards(our_hand, board, all_cards);
        defer self.allocator.free(available);
        
        if (available.len < n_next_cards) {
            // Not enough cards, return uniform distribution
            for (distribution) |*val| {
                val.* = 1.0 / @as(f32, @floatFromInt(n_clusters));
            }
            return distribution;
        }
        
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        
        // Sample possible next cards and calculate distribution
        const n_samples = @min(n_simulations, available.len);
        var sample: u32 = 0;
        
        while (sample < n_samples) : (sample += 1) {
            // Sample next card(s)
            const next_cards = try self.allocator.alloc(Card, n_next_cards);
            defer self.allocator.free(next_cards);
            
            // Sample without replacement
            var used = try self.allocator.alloc(bool, available.len);
            defer self.allocator.free(used);
            @memset(used, false);
            
            for (next_cards) |*card| {
                var idx = random.intRangeLessThan(usize, 0, available.len);
                while (used[idx]) {
                    idx = random.intRangeLessThan(usize, 0, available.len);
                }
                card.* = available[idx];
                used[idx] = true;
            }
            
            // Create new board with next cards
            var new_board = try self.allocator.alloc(Card, board.len + n_next_cards);
            defer self.allocator.free(new_board);
            
            for (board, 0..) |card, i| {
                new_board[i] = card;
            }
            for (next_cards, 0..) |card, i| {
                new_board[board.len + i] = card;
            }
            
            // Calculate EHS for this scenario
            const ehs = try self.calculateEHS(our_hand, new_board, all_cards, 10, seed + sample);
            
            // Map to cluster
            const cluster_id = if (cluster_map) |map| blk: {
                // Create combo hash
                const combo_hash = try self.hashCombo(our_hand, new_board);
                break :blk map.get(combo_hash) orelse 0;
            } else blk: {
                // Simple bucketing based on EHS value
                const bucket = @min(
                    @as(u32, @intFromFloat(ehs * @as(f32, @floatFromInt(n_clusters)))),
                    @as(u32, @intCast(n_clusters - 1)),
                );
                break :blk bucket;
            };
            
            // Add to distribution
            distribution[cluster_id] += 1.0 / @as(f32, @floatFromInt(n_samples));
        }
        
        return distribution;
    }
    
    // Get cards that are still available (not in hand or on board)
    fn getAvailableCards(
        self: *EquityCalculator,
        our_hand: []const Card,
        board: []const Card,
        all_cards: []const Card,
    ) ![]Card {
        var available = std.ArrayList(Card).init(self.allocator);
        
        for (all_cards) |card| {
            var is_available = true;
            
            // Check if in our hand
            for (our_hand) |hand_card| {
                if (card.eql(hand_card)) {
                    is_available = false;
                    break;
                }
            }
            
            // Check if on board
            if (is_available) {
                for (board) |board_card| {
                    if (card.eql(board_card)) {
                        is_available = false;
                        break;
                    }
                }
            }
            
            if (is_available) {
                try available.append(card);
            }
        }
        
        return available.toOwnedSlice();
    }
    
    // Hash a combination of cards for LUT storage
    pub fn hashCombo(self: *EquityCalculator, hand: []const Card, board: []const Card) !u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        
        // Hash hand cards
        for (hand) |card| {
            hasher.update(std.mem.asBytes(&card.eval_card));
        }
        
        // Hash board cards
        for (board) |card| {
            hasher.update(std.mem.asBytes(&card.eval_card));
        }
        
        return hasher.final();
    }
};

// Tests
test "EHS calculation" {
    const allocator = std.testing.allocator;
    var calculator = EquityCalculator.init(allocator);
    
    // Create test hand (AA)
    const our_hand = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "hearts"),
    };
    
    // Create test board (2-3-5 rainbow)
    const board = [_]Card{
        Card.init(2, "spades"),
        Card.init(3, "hearts"),
        Card.init(5, "diamonds"),
    };
    
    // Get all cards
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
    defer allocator.free(all_cards);
    
    // Calculate EHS
    const ehs = try calculator.calculateEHS(&our_hand, &board, all_cards, 100, 42);
    
    // AA on a dry board should have high EHS (> 0.8)
    try std.testing.expect(ehs > 0.7);
    try std.testing.expect(ehs <= 1.0);
}