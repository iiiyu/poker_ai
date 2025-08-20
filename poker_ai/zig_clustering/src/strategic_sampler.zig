const std = @import("std");
const Card = @import("eval_card.zig").Card;

// Strategic sampler for better coverage of important poker hands
pub const StrategicSampler = struct {
    allocator: std.mem.Allocator,
    all_cards: []const Card,
    
    pub fn init(allocator: std.mem.Allocator, all_cards: []const Card) StrategicSampler {
        return StrategicSampler{
            .allocator = allocator,
            .all_cards = all_cards,
        };
    }
    
    // Generate strategically important hand combinations
    pub fn generateStrategicHands(self: *StrategicSampler, max_hands: usize) ![]HandCombo {
        var hands = std.ArrayList(HandCombo).init(self.allocator);
        
        // Priority 1: Pocket pairs (AA, KK, QQ, etc.)
        try self.addPocketPairs(&hands, max_hands / 4);
        
        // Priority 2: Suited connectors (AKs, KQs, etc.)
        try self.addSuitedConnectors(&hands, max_hands / 4);
        
        // Priority 3: Broadway hands (AK, AQ, AJ, KQ, etc.)
        try self.addBroadwayHands(&hands, max_hands / 4);
        
        // Priority 4: Random sampling for diversity
        try self.addRandomHands(&hands, max_hands - hands.items.len);
        
        return hands.toOwnedSlice();
    }
    
    fn addPocketPairs(self: *StrategicSampler, hands: *std.ArrayList(HandCombo), max_count: usize) !void {
        var count: usize = 0;
        
        // Start from high pairs (AA) down to low pairs (22)
        var rank: u8 = 14; // Ace
        while (rank >= 2 and count < max_count) : (rank -= 1) {
            // For each rank, generate pairs from different suits
            for (self.all_cards) |card1| {
                if (card1.rank != rank) continue;
                
                for (self.all_cards) |card2| {
                    if (card2.rank != rank) continue;
                    if (card1.eql(card2)) continue;
                    
                    try hands.append(HandCombo{
                        .card1 = card1,
                        .card2 = card2,
                        .priority = 1,
                    });
                    
                    count += 1;
                    if (count >= max_count) return;
                }
            }
        }
    }
    
    fn addSuitedConnectors(self: *StrategicSampler, hands: *std.ArrayList(HandCombo), max_count: usize) !void {
        var count: usize = 0;
        
        // Generate suited connectors (consecutive ranks, same suit)
        for (self.all_cards) |card1| {
            for (self.all_cards) |card2| {
                // Check if suited
                if (!std.mem.eql(u8, card1.suit, card2.suit)) continue;
                
                // Check if connected (consecutive ranks)
                const rank_diff = if (card1.rank > card2.rank) 
                    card1.rank - card2.rank 
                else 
                    card2.rank - card1.rank;
                    
                if (rank_diff != 1) continue;
                
                try hands.append(HandCombo{
                    .card1 = card1,
                    .card2 = card2,
                    .priority = 2,
                });
                
                count += 1;
                if (count >= max_count) return;
            }
        }
    }
    
    fn addBroadwayHands(self: *StrategicSampler, hands: *std.ArrayList(HandCombo), max_count: usize) !void {
        var count: usize = 0;
        
        // Broadway cards are T, J, Q, K, A (ranks 10-14)
        for (self.all_cards) |card1| {
            if (card1.rank < 10) continue;
            
            for (self.all_cards) |card2| {
                if (card2.rank < 10) continue;
                if (card1.eql(card2)) continue;
                
                // Skip if already added as pair
                if (card1.rank == card2.rank) continue;
                
                try hands.append(HandCombo{
                    .card1 = card1,
                    .card2 = card2,
                    .priority = 3,
                });
                
                count += 1;
                if (count >= max_count) return;
            }
        }
    }
    
    fn addRandomHands(self: *StrategicSampler, hands: *std.ArrayList(HandCombo), max_count: usize) !void {
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        var count: usize = 0;
        while (count < max_count) : (count += 1) {
            const idx1 = random.intRangeLessThan(usize, 0, self.all_cards.len);
            var idx2 = random.intRangeLessThan(usize, 0, self.all_cards.len);
            
            while (idx2 == idx1) {
                idx2 = random.intRangeLessThan(usize, 0, self.all_cards.len);
            }
            
            try hands.append(HandCombo{
                .card1 = self.all_cards[idx1],
                .card2 = self.all_cards[idx2],
                .priority = 4,
            });
        }
    }
    
    pub const HandCombo = struct {
        card1: Card,
        card2: Card,
        priority: u8, // 1 = highest priority (pocket pairs), 4 = lowest (random)
    };
    
    // Generate board cards with strategic diversity
    pub fn generateStrategicBoards(
        self: *StrategicSampler,
        hand: []const Card,
        board_size: usize,
        max_boards: usize,
    ) ![][]Card {
        var boards = std.ArrayList([]Card).init(self.allocator);
        
        // Generate diverse board textures
        const boards_per_type = max_boards / 4;
        
        // Type 1: Dry boards (rainbow, no straights/flushes)
        try self.addDryBoards(&boards, hand, board_size, boards_per_type);
        
        // Type 2: Wet boards (coordinated, potential draws)
        try self.addWetBoards(&boards, hand, board_size, boards_per_type);
        
        // Type 3: Monotone boards (all same suit)
        try self.addMonotoneBoards(&boards, hand, board_size, boards_per_type);
        
        // Type 4: Random boards for diversity
        try self.addRandomBoards(&boards, hand, board_size, max_boards - boards.items.len);
        
        return boards.toOwnedSlice();
    }
    
    fn addDryBoards(
        self: *StrategicSampler,
        boards: *std.ArrayList([]Card),
        hand: []const Card,
        board_size: usize,
        max_count: usize,
    ) !void {
        _ = self;
        _ = boards;
        _ = hand;
        _ = board_size;
        _ = max_count;
        // Implementation would generate rainbow boards with gaps between ranks
    }
    
    fn addWetBoards(
        self: *StrategicSampler,
        boards: *std.ArrayList([]Card),
        hand: []const Card,
        board_size: usize,
        max_count: usize,
    ) !void {
        _ = self;
        _ = boards;
        _ = hand;
        _ = board_size;
        _ = max_count;
        // Implementation would generate coordinated boards with draws
    }
    
    fn addMonotoneBoards(
        self: *StrategicSampler,
        boards: *std.ArrayList([]Card),
        hand: []const Card,
        board_size: usize,
        max_count: usize,
    ) !void {
        _ = self;
        _ = boards;
        _ = hand;
        _ = board_size;
        _ = max_count;
        // Implementation would generate all same suit boards
    }
    
    fn addRandomBoards(
        self: *StrategicSampler,
        boards: *std.ArrayList([]Card),
        hand: []const Card,
        board_size: usize,
        max_count: usize,
    ) !void {
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        var count: usize = 0;
        while (count < max_count) : (count += 1) {
            var board = try self.allocator.alloc(Card, board_size);
            var used = try self.allocator.alloc(bool, self.all_cards.len);
            defer self.allocator.free(used);
            @memset(used, false);
            
            // Mark hand cards as used
            for (hand) |card| {
                for (self.all_cards, 0..) |c, i| {
                    if (c.eql(card)) {
                        used[i] = true;
                        break;
                    }
                }
            }
            
            // Generate random board
            for (board) |*card| {
                var idx = random.intRangeLessThan(usize, 0, self.all_cards.len);
                while (used[idx]) {
                    idx = random.intRangeLessThan(usize, 0, self.all_cards.len);
                }
                card.* = self.all_cards[idx];
                used[idx] = true;
            }
            
            try boards.append(board);
        }
    }
};