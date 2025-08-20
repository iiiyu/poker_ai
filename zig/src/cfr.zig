// Monte Carlo Counterfactual Regret Minimization (MCCFR) Algorithm
// Core CFR implementation for poker AI training

const std = @import("std");
const game_state = @import("game_state.zig");
const strategy_table = @import("strategy_table.zig");
const lookup_tables = @import("lookup_tables.zig");
const hand_eval = @import("hand_eval.zig");

// CFR algorithm configuration
pub const CFRConfig = struct {
    iterations: u32 = 1000,
    exploration_probability: f64 = 0.6,
    prune_threshold: f64 = -300.0,
    discount_alpha: f64 = 1.5,
    discount_beta: f64 = 0.0,
    
    pub fn default() CFRConfig {
        return CFRConfig{};
    }
};

// Information set node in the game tree
pub const InfoSetNode = struct {
    info_set: []u8, // Unique identifier for this information set
    regret_sum: []f64, // Cumulative regret for each action
    strategy_sum: []f64, // Cumulative strategy for each action
    num_actions: u8,
    reach_probability: f64,
    
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, info_set: []const u8, num_actions: u8) !Self {
        const owned_info_set = try allocator.dupe(u8, info_set);
        
        return Self{
            .info_set = owned_info_set,
            .regret_sum = try allocator.alloc(f64, num_actions),
            .strategy_sum = try allocator.alloc(f64, num_actions),
            .num_actions = num_actions,
            .reach_probability = 1.0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.info_set);
        self.allocator.free(self.regret_sum);
        self.allocator.free(self.strategy_sum);
    }
    
    // Calculate current strategy using regret matching
    pub fn getStrategy(self: *Self, realization_weight: f64) ![]f64 {
        var strategy = try self.allocator.alloc(f64, self.num_actions);
        var normalizing_sum: f64 = 0.0;
        
        // Calculate positive regrets
        for (self.regret_sum, 0..) |regret, i| {
            strategy[i] = if (regret > 0) regret else 0;
            normalizing_sum += strategy[i];
        }
        
        // Normalize to create probability distribution
        if (normalizing_sum > 0) {
            for (strategy) |*prob| {
                prob.* /= normalizing_sum;
            }
        } else {
            // Uniform random strategy if no positive regrets
            const uniform_prob = 1.0 / @as(f64, @floatFromInt(self.num_actions));
            for (strategy) |*prob| {
                prob.* = uniform_prob;
            }
        }
        
        // Update strategy sum for average strategy calculation
        for (strategy, 0..) |prob, i| {
            self.strategy_sum[i] += realization_weight * prob;
        }
        
        return strategy;
    }
    
    // Get average strategy over all iterations
    pub fn getAverageStrategy(self: *Self) ![]f64 {
        var avg_strategy = try self.allocator.alloc(f64, self.num_actions);
        var normalizing_sum: f64 = 0.0;
        
        for (self.strategy_sum) |sum| {
            normalizing_sum += sum;
        }
        
        if (normalizing_sum > 0) {
            for (self.strategy_sum, 0..) |sum, i| {
                avg_strategy[i] = sum / normalizing_sum;
            }
        } else {
            const uniform_prob = 1.0 / @as(f64, @floatFromInt(self.num_actions));
            for (avg_strategy) |*prob| {
                prob.* = uniform_prob;
            }
        }
        
        return avg_strategy;
    }
};

// Monte Carlo CFR trainer
pub const MCCFRTrainer = struct {
    config: CFRConfig,
    strategy_table: *strategy_table.StrategyTable,
    abstraction_table: *lookup_tables.AbstractionTable,
    hand_evaluator: *hand_eval.HandEvaluator,
    
    // Training state
    iteration: u32,
    nodes: std.HashMap(u64, InfoSetNode, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    
    allocator: std.mem.Allocator,
    rng: std.Random.DefaultPrng,
    
    const Self = @This();
    
    pub fn init(
        allocator: std.mem.Allocator,
        config: CFRConfig,
        strategy_table_ptr: *strategy_table.StrategyTable,
        abstraction_table_ptr: *lookup_tables.AbstractionTable,
        hand_evaluator_ptr: *hand_eval.HandEvaluator,
    ) !Self {
        return Self{
            .config = config,
            .strategy_table = strategy_table_ptr,
            .abstraction_table = abstraction_table_ptr,
            .hand_evaluator = hand_evaluator_ptr,
            .iteration = 0,
            .nodes = std.HashMap(u64, InfoSetNode, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.nodes.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.nodes.deinit();
    }
    
    // Run CFR training for specified number of iterations
    pub fn train(self: *Self) !void {
        std.log.info("Starting MCCFR training for {} iterations", .{self.config.iterations});
        
        while (self.iteration < self.config.iterations) {
            // Create random game scenario
            var game = try self.createRandomGame();
            defer game.deinit();
            
            // Run CFR for each player
            for (0..game.num_players) |player_id| {
                const utility = try self.cfr(&game, @intCast(player_id), 1.0, 1.0);
                _ = utility; // Utility is used internally
            }
            
            self.iteration += 1;
            
            if (self.iteration % 100 == 0) {
                std.log.info("Completed iteration {}", .{self.iteration});
            }
        }
        
        // Update strategy table with final strategies
        try self.updateStrategyTable();
        
        std.log.info("MCCFR training completed");
    }
    
    // Recursive CFR algorithm
    fn cfr(self: *Self, game_state_ptr: *game_state.GameState, player: u8, p0: f64, p1: f64) !f64 {
        if (game_state_ptr.isTerminal()) {
            return self.getUtility(game_state_ptr, player);
        }
        
        const current_player = game_state_ptr.current_player;
        
        // Get information set for current player
        const info_set_data = try game_state_ptr.getInfoSet(current_player);
        defer self.allocator.free(info_set_data);
        
        const info_set_hash = std.hash_map.hashString(info_set_data);
        
        // Get available actions
        const actions = try self.getAvailableActions(game_state_ptr);
        defer self.allocator.free(actions);
        
        // Get or create node for this information set
        var node = try self.getOrCreateNode(info_set_hash, info_set_data, @intCast(actions.len));
        
        // Get current strategy
        const realization_weight = if (current_player == 0) p0 else p1;
        const strategy = try node.getStrategy(realization_weight);
        defer self.allocator.free(strategy);
        
        var utilities = try self.allocator.alloc(f64, actions.len);
        defer self.allocator.free(utilities);
        
        var node_utility: f64 = 0.0;
        
        // Calculate utility for each action
        for (actions, 0..) |action, i| {
            // Create new game state with this action
            var new_game = try self.cloneGameState(game_state_ptr);
            defer new_game.deinit();
            
            _ = try new_game.applyAction(action);
            
            // Advance to next round if betting is complete
            if (new_game.isBettingComplete()) {
                new_game.nextRound();
            }
            
            // Calculate opponent reach probabilities
            const new_p0 = if (current_player == 0) p0 * strategy[i] else p0;
            const new_p1 = if (current_player == 1) p1 * strategy[i] else p1;
            
            utilities[i] = try self.cfr(&new_game, player, new_p0, new_p1);
            node_utility += strategy[i] * utilities[i];
        }
        
        // Update regrets for the acting player
        if (current_player == player) {
            const counterfactual_prob = if (player == 0) p1 else p0;
            
            for (utilities, 0..) |utility, i| {
                const regret = utility - node_utility;
                node.regret_sum[i] += counterfactual_prob * regret;
            }
        }
        
        return node_utility;
    }
    
    // Helper functions
    fn createRandomGame(self: *Self) !game_state.GameState {
        var game = try game_state.GameState.init(self.allocator, 2, 5, 10);
        
        // Deal random hands
        var deck = std.ArrayList(u8).init(self.allocator);
        defer deck.deinit();
        
        for (0..52) |i| {
            try deck.append(@intCast(i));
        }
        
        // Shuffle deck
        self.rng.random().shuffle(u8, deck.items);
        
        // Deal hole cards
        const hands = [2][2]u8{
            .{ deck.items[0], deck.items[1] },
            .{ deck.items[2], deck.items[3] },
        };
        
        game.dealHoleCards(&hands);
        
        return game;
    }
    
    fn getAvailableActions(self: *Self, game_state_ptr: *game_state.GameState) ![]game_state.Action {
        // self is used for allocator access
        var actions = std.ArrayList(game_state.Action).init(self.allocator);
        
        const current_bet = game_state_ptr.current_bet;
        const player = &game_state_ptr.players[game_state_ptr.current_player];
        
        // Always allow fold
        try actions.append(game_state.Action.fold());
        
        // Check or call
        if (current_bet == player.bet_this_round) {
            try actions.append(game_state.Action.check());
        } else {
            try actions.append(game_state.Action.call());
        }
        
        // Raise options
        const min_raise = current_bet + game_state_ptr.big_blind;
        if (min_raise <= player.stack + player.bet_this_round) {
            try actions.append(game_state.Action.raise(min_raise));
        }
        
        return actions.toOwnedSlice();
    }
    
    fn getOrCreateNode(self: *Self, hash: u64, info_set: []const u8, num_actions: u8) !*InfoSetNode {
        if (self.nodes.getPtr(hash)) |node| {
            return node;
        }
        
        const new_node = try InfoSetNode.init(self.allocator, info_set, num_actions);
        try self.nodes.put(hash, new_node);
        return self.nodes.getPtr(hash).?;
    }
    
    fn cloneGameState(self: *Self, original: *game_state.GameState) !game_state.GameState {
        var clone = try game_state.GameState.init(
            self.allocator,
            original.num_players,
            original.small_blind,
            original.big_blind,
        );
        
        // Copy game state
        clone.players = original.players;
        clone.active_players = original.active_players;
        clone.round = original.round;
        clone.board = original.board;
        clone.board_size = original.board_size;
        clone.current_player = original.current_player;
        clone.dealer_button = original.dealer_button;
        clone.pot = original.pot;
        clone.current_bet = original.current_bet;
        clone.last_raiser = original.last_raiser;
        
        // Copy action sequences
        for (original.actions.items) |action| {
            try clone.actions.append(action);
        }
        for (original.action_sequence.items) |action| {
            try clone.action_sequence.append(action);
        }
        
        return clone;
    }
    
    fn getUtility(self: *Self, game_state_ptr: *game_state.GameState, player: u8) f64 {
        _ = self;
        
        if (game_state_ptr.active_players == 1) {
            // All others folded
            return if (game_state_ptr.players[player].is_active) 
                @floatFromInt(game_state_ptr.pot) else 
                -@as(f64, @floatFromInt(game_state_ptr.players[player].total_bet));
        }
        
        // Showdown - simplified evaluation
        // In practice, this would use proper hand evaluation
        return 0.0; // Placeholder
    }
    
    fn updateStrategyTable(self: *Self) !void {
        // Update the strategy table with learned strategies
        var iterator = self.nodes.iterator();
        while (iterator.next()) |entry| {
            const node = entry.value_ptr;
            const avg_strategy = try node.getAverageStrategy();
            defer self.allocator.free(avg_strategy);
            
            // Store in strategy table (implementation depends on table format)
            // For now, just log the strategies
            std.log.debug("Info set: {} -> Strategy: {any}", .{ std.fmt.fmtSliceHexLower(node.info_set), avg_strategy });
        }
    }
};

test "cfr config initialization" {
    const testing = std.testing;
    
    const config = CFRConfig.default();
    try testing.expectEqual(@as(u32, 1000), config.iterations);
    try testing.expectEqual(@as(f64, 0.6), config.exploration_probability);
}

test "info set node creation" {
    const testing = std.testing;
    
    const info_set = "test_info_set";
    var node = try InfoSetNode.init(testing.allocator, info_set, 3);
    defer node.deinit();
    
    try testing.expectEqual(@as(u8, 3), node.num_actions);
    try testing.expectEqualStrings(info_set, node.info_set);
    try testing.expectEqual(@as(f64, 1.0), node.reach_probability);
}