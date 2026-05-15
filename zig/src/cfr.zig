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

        // Initialize iteration weights for CFR+ or discounted CFR
        var iteration_weight: f64 = 1.0;
        const use_cfr_plus = self.config.discount_beta > 0.0;

        while (self.iteration < self.config.iterations) {
            std.log.debug("Starting iteration {}", .{self.iteration});

            // Update iteration weight for CFR+ discounting
            if (use_cfr_plus) {
                iteration_weight = std.math.pow(f64, @floatFromInt(self.iteration + 1), self.config.discount_alpha);
            }

            // Create random game scenario
            var game = try self.createRandomGame();
            defer game.deinit();

            // Determine if we should sample or traverse full tree
            const use_sampling = self.rng.random().float(f64) < self.config.exploration_probability;

            // Run CFR for each player with Monte Carlo sampling
            for (0..game.num_players) |player_id| {
                const utility = if (use_sampling)
                    try self.mccfr(&game, @intCast(player_id), 1.0, 1.0, iteration_weight)
                else
                    try self.cfr(&game, @intCast(player_id), 1.0, 1.0);

                // Track average utility for convergence monitoring
                if (self.iteration > 0) {
                    const alpha = 0.01; // Exponential moving average
                    _ = utility * alpha; // Update moving average
                }
            }

            // Apply regret pruning periodically
            if (self.iteration % 100 == 0 and self.iteration > 0) {
                try self.pruneRegrets();
            }

            self.iteration += 1;

            if (self.iteration % 100 == 0) {
                const table_size = self.nodes.count();
                std.log.info("Iteration {}: {} info sets in memory", .{ self.iteration, table_size });
            }

            if (self.iteration % 1000 == 0) {
                // Save checkpoint
                try self.updateStrategyTable();
            }
        }

        // Update strategy table with final strategies
        try self.updateStrategyTable();

        std.log.info("MCCFR training completed with {} total info sets", .{self.nodes.count()});
    }

    // Monte Carlo CFR with importance sampling
    fn mccfr(self: *Self, game_state_ptr: *game_state.GameState, player: u8, p0: f64, p1: f64, weight: f64) !f64 {
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
        const strategy = try node.getStrategy(realization_weight * weight);
        defer self.allocator.free(strategy);

        // For Monte Carlo sampling, we sample one action instead of traversing all
        const sampled_action_idx = self.sampleAction(strategy);
        const sampled_action = actions[sampled_action_idx];

        // Create new game state with sampled action
        var new_game = try self.cloneGameState(game_state_ptr);
        defer new_game.deinit();

        _ = try new_game.applyAction(sampled_action);

        // Advance to next round if betting is complete
        if (new_game.isBettingComplete()) {
            new_game.nextRound();
        }

        // Calculate opponent reach probabilities
        const sampled_prob = strategy[sampled_action_idx];
        const new_p0 = if (current_player == 0) p0 * sampled_prob else p0;
        const new_p1 = if (current_player == 1) p1 * sampled_prob else p1;

        // Recursively traverse with sampled action
        const utility = try self.mccfr(&new_game, player, new_p0, new_p1, weight);

        // Update regrets only for the acting player
        if (current_player == player) {
            const counterfactual_prob = if (player == 0) p1 else p0;

            // Calculate counterfactual values for all actions
            for (actions, 0..) |action, i| {
                if (i == sampled_action_idx) {
                    // For sampled action, use actual utility
                    const regret = utility - utility * sampled_prob;
                    node.regret_sum[i] += counterfactual_prob * weight * regret;
                } else {
                    if (sampled_prob == 0.0) continue;
                    // For unsampled actions, estimate counterfactual value
                    // This is where importance sampling helps reduce variance
                    var action_game = try self.cloneGameState(game_state_ptr);
                    defer action_game.deinit();

                    _ = try action_game.applyAction(action);
                    if (action_game.isBettingComplete()) {
                        action_game.nextRound();
                    }

                    const action_utility = if (action_game.isTerminal())
                        self.getUtility(&action_game, player)
                    else
                        utility; // Use sampled utility as baseline

                    const regret = action_utility - utility;
                    node.regret_sum[i] += counterfactual_prob * weight * regret / sampled_prob;
                }
            }
        }

        return utility;
    }

    // Sample action according to strategy distribution
    fn sampleAction(self: *Self, strategy: []const f64) usize {
        const rand = self.rng.random().float(f64);
        var cumulative: f64 = 0.0;

        for (strategy, 0..) |prob, i| {
            cumulative += prob;
            if (rand <= cumulative) {
                return i;
            }
        }

        // Fallback to last action
        return strategy.len - 1;
    }

    // Prune regrets below threshold to save memory
    fn pruneRegrets(self: *Self) !void {
        var iterator = self.nodes.iterator();
        var pruned_count: u32 = 0;

        while (iterator.next()) |entry| {
            const node = entry.value_ptr;
            for (node.regret_sum) |*regret| {
                if (regret.* < self.config.prune_threshold) {
                    regret.* = 0.0;
                    pruned_count += 1;
                }
            }
        }

        if (pruned_count > 0) {
            std.log.debug("Pruned {} negative regrets", .{pruned_count});
        }
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
    pub fn createRandomGame(self: *Self) !game_state.GameState {
        var game = try game_state.GameState.init(self.allocator, 2, 5, 10);

        // Deal random hands
        var deck = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer deck.deinit(self.allocator);

        for (0..52) |i| {
            try deck.append(self.allocator, @intCast(i));
        }

        // Shuffle deck
        self.rng.random().shuffle(u8, deck.items);

        // Deal hole cards directly to players
        game.players[0].hand.cards[0] = deck.items[0];
        game.players[0].hand.cards[1] = deck.items[1];
        game.players[1].hand.cards[0] = deck.items[2];
        game.players[1].hand.cards[1] = deck.items[3];

        return game;
    }

    pub fn getAvailableActions(self: *Self, game_state_ptr: *game_state.GameState) ![]game_state.Action {
        // self is used for allocator access
        var actions = try std.ArrayList(game_state.Action).initCapacity(self.allocator, 0);

        const current_bet = game_state_ptr.current_bet;
        const player = &game_state_ptr.players[game_state_ptr.current_player];

        // Always allow fold
        try actions.append(self.allocator, game_state.Action.fold());

        // Check or call
        if (current_bet == player.bet_this_round) {
            try actions.append(self.allocator, game_state.Action.check());
        } else {
            try actions.append(self.allocator, game_state.Action.call());
        }

        // Raise options
        const min_raise = current_bet + game_state_ptr.big_blind;
        if (min_raise <= player.stack + player.bet_this_round) {
            try actions.append(self.allocator, game_state.Action.raise(min_raise));
        }

        return actions.toOwnedSlice(self.allocator);
    }

    pub fn getOrCreateNode(self: *Self, hash: u64, info_set: []const u8, num_actions: u8) !*InfoSetNode {
        if (self.nodes.getPtr(hash)) |node| {
            return node;
        }

        const new_node = try InfoSetNode.init(self.allocator, info_set, num_actions);
        try self.nodes.put(hash, new_node);
        return self.nodes.getPtr(hash).?;
    }

    pub fn cloneGameState(self: *Self, original: *game_state.GameState) !game_state.GameState {
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
            try clone.actions.append(self.allocator, action);
        }
        for (original.action_sequence.items) |action| {
            try clone.action_sequence.append(self.allocator, action);
        }

        return clone;
    }

    pub fn getUtility(self: *Self, game_state_ptr: *game_state.GameState, player: u8) f64 {
        if (game_state_ptr.active_players == 1) {
            // All others folded
            return if (game_state_ptr.players[player].is_active)
                @floatFromInt(game_state_ptr.pot)
            else
                -@as(f64, @floatFromInt(game_state_ptr.players[player].total_bet));
        }

        // Showdown - evaluate hands
        const player_cards = game_state_ptr.players[player].hand.cards;
        const opponent = if (player == 0) @as(u8, 1) else 0;
        const opponent_cards = game_state_ptr.players[opponent].hand.cards;

        // Build 7-card hands (2 hole cards + 5 board cards)
        var player_hand: [7]hand_eval.Card = undefined;
        var opponent_hand: [7]hand_eval.Card = undefined;

        // Convert hole cards to evaluator format
        player_hand[0] = self.convertCardToEvalFormat(player_cards[0]);
        player_hand[1] = self.convertCardToEvalFormat(player_cards[1]);
        opponent_hand[0] = self.convertCardToEvalFormat(opponent_cards[0]);
        opponent_hand[1] = self.convertCardToEvalFormat(opponent_cards[1]);

        // Add board cards
        for (0..game_state_ptr.board_size) |i| {
            const eval_card = self.convertCardToEvalFormat(game_state_ptr.board[i]);
            player_hand[i + 2] = eval_card;
            opponent_hand[i + 2] = eval_card;
        }

        // Fill remaining cards with 0 if board is not complete
        for (game_state_ptr.board_size..5) |i| {
            player_hand[i + 2] = 0;
            opponent_hand[i + 2] = 0;
        }

        // Evaluate hands
        const player_rank = if (game_state_ptr.board_size == 5)
            self.hand_evaluator.evaluateSeven(player_hand)
        else if (game_state_ptr.board_size == 3)
            self.hand_evaluator.evaluateFive([5]hand_eval.Card{ player_hand[0], player_hand[1], player_hand[2], player_hand[3], player_hand[4] })
        else
            hand_eval.MAX_HIGH_CARD; // Default for incomplete boards

        const opponent_rank = if (game_state_ptr.board_size == 5)
            self.hand_evaluator.evaluateSeven(opponent_hand)
        else if (game_state_ptr.board_size == 3)
            self.hand_evaluator.evaluateFive([5]hand_eval.Card{ opponent_hand[0], opponent_hand[1], opponent_hand[2], opponent_hand[3], opponent_hand[4] })
        else
            hand_eval.MAX_HIGH_CARD;

        // Lower rank = better hand
        if (player_rank < opponent_rank) {
            // Player wins
            return @floatFromInt(game_state_ptr.pot);
        } else if (player_rank > opponent_rank) {
            // Player loses
            return -@as(f64, @floatFromInt(game_state_ptr.players[player].total_bet));
        } else {
            // Split pot
            return @as(f64, @floatFromInt(game_state_ptr.pot)) / 2.0 -
                @as(f64, @floatFromInt(game_state_ptr.players[player].total_bet));
        }
    }

    fn convertCardToEvalFormat(self: *Self, card_idx: u8) hand_eval.Card {
        _ = self;
        // Convert from 0-51 index to evaluator format
        const rank = card_idx % 13;
        const suit = card_idx / 13;

        const rank_prime = hand_eval.PRIMES[rank];
        const bitrank: u32 = @as(u32, 1) << @intCast(rank + 16);
        const suit_bits: u32 = (@as(u32, 1) << @intCast(suit)) << 12;
        const rank_bits: u32 = @as(u32, rank) << 8;

        return bitrank | suit_bits | rank_bits | rank_prime;
    }

    fn updateStrategyTable(self: *Self) !void {
        // Update the strategy table with learned strategies
        var iterator = self.nodes.iterator();
        var updated_count: u32 = 0;

        while (iterator.next()) |entry| {
            const node = entry.value_ptr;
            const info_set_hash = entry.key_ptr.*;
            const avg_strategy = try node.getAverageStrategy();
            defer self.allocator.free(avg_strategy);

            // Create action types from the number of actions
            const action_types = try self.allocator.alloc(game_state.ActionType, node.num_actions);
            defer self.allocator.free(action_types);

            // Map to standard actions (fold, call/check, raise)
            for (action_types, 0..) |*action_type, i| {
                action_type.* = switch (i) {
                    0 => .fold,
                    1 => .call, // or check
                    2 => .raise,
                    else => .call, // default
                };
            }

            // Get or create strategy profile in the strategy table
            const profile = try self.strategy_table.getOrCreateStrategy(info_set_hash, action_types);

            // Update the profile with learned strategy
            for (avg_strategy, 0..) |prob, i| {
                profile.action_probs.probabilities[i] = prob;
            }

            // Copy regret and strategy sums for persistence
            for (node.regret_sum, 0..) |regret, i| {
                profile.regret_sum[i] = regret;
            }
            for (node.strategy_sum, 0..) |sum, i| {
                profile.strategy_sum[i] = sum;
            }

            profile.reach_count = @intCast(self.iteration);
            updated_count += 1;
        }

        std.log.info("Updated {} strategies in strategy table", .{updated_count});

        // Calculate and log convergence metrics
        const avg_strategy_distance = try self.calculateConvergence();
        std.log.info("Average strategy distance from uniform: {d:.6}", .{avg_strategy_distance});
    }

    pub fn calculateConvergence(self: *Self) !f64 {
        var total_distance: f64 = 0.0;
        var count: u32 = 0;

        var iterator = self.nodes.iterator();
        while (iterator.next()) |entry| {
            const node = entry.value_ptr;
            const avg_strategy = try node.getAverageStrategy();
            defer self.allocator.free(avg_strategy);

            // Calculate L2 distance from uniform distribution
            const uniform_prob = 1.0 / @as(f64, @floatFromInt(node.num_actions));
            var distance: f64 = 0.0;

            for (avg_strategy) |prob| {
                const diff = prob - uniform_prob;
                distance += diff * diff;
            }

            total_distance += std.math.sqrt(distance);
            count += 1;
        }

        return if (count > 0) total_distance / @as(f64, @floatFromInt(count)) else 0.0;
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
