// Test MCCFR convergence on Kuhn Poker
// Kuhn poker is a simple game that should converge to known Nash equilibrium

const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");

// Kuhn Poker implementation for testing convergence
const KuhnPoker = struct {
    // Kuhn poker has 3 cards: Jack(0), Queen(1), King(2)
    // Each player gets 1 card, 1 card remains unseen
    // Actions: Pass/Bet for player 1, Pass/Bet or Fold/Call for player 2
    
    const Card = enum(u8) {
        jack = 0,
        queen = 1,
        king = 2,
    };
    
    const Action = enum(u8) {
        pass = 0,
        bet = 1,
        fold = 2,
        call = 3,
    };
    
    const Player = enum(u8) {
        player1 = 0,
        player2 = 1,
    };
    
    pub const State = struct {
        cards: [2]Card,
        history: std.ArrayList(Action),
        pot: [2]i32,
        current_player: Player,
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator, card1: Card, card2: Card) !State {
            return State{
                .cards = .{ card1, card2 },
                .history = std.ArrayList(Action).init(allocator),
                .pot = .{ 1, 1 }, // Ante of 1 for each player
                .current_player = .player1,
                .allocator = allocator,
            };
        }
        
        pub fn deinit(self: *State) void {
            self.history.deinit();
        }
        
        pub fn clone(self: *State) !State {
            var new_state = State{
                .cards = self.cards,
                .history = std.ArrayList(Action).init(self.allocator),
                .pot = self.pot,
                .current_player = self.current_player,
                .allocator = self.allocator,
            };
            
            for (self.history.items) |action| {
                try new_state.history.append(allocator, action);
            }
            
            return new_state;
        }
        
        pub fn isTerminal(self: *State) bool {
            const h = self.history.items;
            
            if (h.len == 0) return false;
            
            // Check for terminal sequences
            if (h.len == 2) {
                // Pass-Pass
                if (h[0] == .pass and h[1] == .pass) return true;
                // Bet-Fold
                if (h[0] == .bet and h[1] == .fold) return true;
                // Bet-Call
                if (h[0] == .bet and h[1] == .call) return true;
            }
            
            if (h.len == 3) {
                // Pass-Bet-Fold
                if (h[0] == .pass and h[1] == .bet and h[2] == .fold) return true;
                // Pass-Bet-Call
                if (h[0] == .pass and h[1] == .bet and h[2] == .call) return true;
            }
            
            return false;
        }
        
        pub fn getUtility(self: *State, player: u8) f32 {
            if (!self.isTerminal()) return 0.0;
            
            const h = self.history.items;
            const player_card = self.cards[player];
            const opponent_card = self.cards[1 - player];
            
            var payoff: i32 = 0;
            
            if (h.len == 2) {
                if (h[0] == .pass and h[1] == .pass) {
                    // Showdown with pot of 2
                    if (@intFromEnum(player_card) > @intFromEnum(opponent_card)) {
                        payoff = 1;
                    } else {
                        payoff = -1;
                    }
                } else if (h[0] == .bet and h[1] == .fold) {
                    // Player 1 wins
                    payoff = if (player == 0) 1 else -1;
                } else if (h[0] == .bet and h[1] == .call) {
                    // Showdown with pot of 4
                    if (@intFromEnum(player_card) > @intFromEnum(opponent_card)) {
                        payoff = 2;
                    } else {
                        payoff = -2;
                    }
                }
            } else if (h.len == 3) {
                if (h[0] == .pass and h[1] == .bet and h[2] == .fold) {
                    // Player 2 wins
                    payoff = if (player == 1) 1 else -1;
                } else if (h[0] == .pass and h[1] == .bet and h[2] == .call) {
                    // Showdown with pot of 4
                    if (@intFromEnum(player_card) > @intFromEnum(opponent_card)) {
                        payoff = 2;
                    } else {
                        payoff = -2;
                    }
                }
            }
            
            return @floatFromInt(payoff);
        }
        
        pub fn getLegalActions(self: *State) []const Action {
            const h = self.history.items;
            
            if (h.len == 0) {
                // Player 1 can pass or bet
                return &[_]Action{ .pass, .bet };
            } else if (h.len == 1) {
                if (h[0] == .pass) {
                    // Player 2 can pass or bet
                    return &[_]Action{ .pass, .bet };
                } else {
                    // Player 2 can fold or call
                    return &[_]Action{ .fold, .call };
                }
            } else if (h.len == 2 and h[0] == .pass and h[1] == .bet) {
                // Player 1 can fold or call
                return &[_]Action{ .fold, .call };
            }
            
            return &[_]Action{};
        }
        
        pub fn applyAction(self: *State, action: Action) !void {
            try self.history.append(allocator, action);
            
            // Update current player
            if (self.current_player == .player1) {
                self.current_player = .player2;
            } else {
                self.current_player = .player1;
            }
            
            // Update pot for bets and calls
            if (action == .bet or action == .call) {
                const player_idx = if (self.current_player == .player2) 0 else 1;
                self.pot[player_idx] += 1;
            }
        }
        
        pub fn getInfoSetString(self: *State, player: u8) ![]u8 {
            var buffer = std.ArrayList(u8).init(self.allocator);
            
            // Add player's card
            const card_char: u8 = switch (self.cards[player]) {
                .jack => 'J',
                .queen => 'Q',
                .king => 'K',
            };
            try buffer.append(allocator, card_char);
            
            // Add action history
            for (self.history.items) |action| {
                const action_char: u8 = switch (action) {
                    .pass => 'p',
                    .bet => 'b',
                    .fold => 'f',
                    .call => 'c',
                };
                try buffer.append(allocator, action_char);
            }
            
            return buffer.toOwnedSlice();
        }
    };
};

// Simplified CFR for Kuhn Poker
const KuhnCFR = struct {
    regret_sum: std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    strategy_sum: std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) KuhnCFR {
        return .{
            .regret_sum = std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .strategy_sum = std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *KuhnCFR) void {
        var iter = self.regret_sum.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.regret_sum.deinit();
        
        iter = self.strategy_sum.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.strategy_sum.deinit();
    }
    
    fn hashInfoSet(info_set: []const u8) u64 {
        return std.hash.Wyhash.hash(0, info_set);
    }
    
    pub fn getStrategy(self: *KuhnCFR, info_set: []const u8, num_actions: usize) ![]f32 {
        const hash = hashInfoSet(info_set);
        
        if (self.regret_sum.get(hash)) |regrets| {
            var strategy = try self.allocator.alloc(f32, num_actions);
            var normalizing_sum: f32 = 0.0;
            
            for (regrets, 0..) |regret, i| {
                strategy[i] = if (regret > 0) regret else 0;
                normalizing_sum += strategy[i];
            }
            
            if (normalizing_sum > 0) {
                for (strategy) |*s| {
                    s.* /= normalizing_sum;
                }
            } else {
                const uniform = 1.0 / @as(f32, @floatFromInt(num_actions));
                for (strategy) |*s| {
                    s.* = uniform;
                }
            }
            
            return strategy;
        } else {
            // Initialize with uniform strategy
            const strategy = try self.allocator.alloc(f32, num_actions);
            const uniform = 1.0 / @as(f32, @floatFromInt(num_actions));
            for (strategy) |*s| {
                s.* = uniform;
            }
            
            // Initialize regret sum
            const regrets = try self.allocator.alloc(f32, num_actions);
            @memset(regrets, 0.0);
            try self.regret_sum.put(hash, regrets);
            
            // Initialize strategy sum
            const strat_sum = try self.allocator.alloc(f32, num_actions);
            @memset(strat_sum, 0.0);
            try self.strategy_sum.put(hash, strat_sum);
            
            return strategy;
        }
    }
    
    pub fn cfr(self: *KuhnCFR, state: *KuhnPoker.State, player: u8, p0: f32, p1: f32) !f32 {
        if (state.isTerminal()) {
            return state.getUtility(player);
        }
        
        const current_player = @intFromEnum(state.current_player);
        const info_set = try state.getInfoSetString(current_player);
        defer self.allocator.free(info_set);
        
        const actions = state.getLegalActions();
        const strategy = try self.getStrategy(info_set, actions.len);
        defer self.allocator.free(strategy);
        
        var util = try self.allocator.alloc(f32, actions.len);
        defer self.allocator.free(util);
        
        var node_util: f32 = 0.0;
        
        for (actions, 0..) |action, i| {
            var new_state = try state.clone();
            defer new_state.deinit();
            
            try new_state.applyAction(action);
            
            const new_p0 = if (current_player == 0) p0 * strategy[i] else p0;
            const new_p1 = if (current_player == 1) p1 * strategy[i] else p1;
            
            util[i] = try self.cfr(&new_state, player, new_p0, new_p1);
            node_util += strategy[i] * util[i];
        }
        
        if (current_player == player) {
            const hash = hashInfoSet(info_set);
            const regrets = self.regret_sum.get(hash).?;
            const strat_sum = self.strategy_sum.get(hash).?;
            
            const cf_reach = if (player == 0) p1 else p0;
            
            for (util, 0..) |u, i| {
                regrets[i] += cf_reach * (u - node_util);
                strat_sum[i] += (if (player == 0) p0 else p1) * strategy[i];
            }
        }
        
        return node_util;
    }
    
    pub fn train(self: *KuhnCFR, iterations: u32) !void {
        var prng = std.Random.DefaultPrng.init(42);
        const rng = prng.random();
        
        var iter: u32 = 0;
        while (iter < iterations) : (iter += 1) {
            // Sample random card permutation
            var cards = [_]KuhnPoker.Card{ .jack, .queen, .king };
            rng.shuffle(KuhnPoker.Card, &cards);
            
            var state = try KuhnPoker.State.init(self.allocator, cards[0], cards[1]);
            defer state.deinit();
            
            // Run CFR for both players
            _ = try self.cfr(&state, 0, 1.0, 1.0);
            _ = try self.cfr(&state, 1, 1.0, 1.0);
            
            if (iter % 1000 == 0) {
                std.log.info("Iteration {}", .{iter});
            }
        }
    }
    
    pub fn getAverageStrategy(self: *KuhnCFR, info_set: []const u8) ?[]f32 {
        const hash = hashInfoSet(info_set);
        
        if (self.strategy_sum.get(hash)) |strat_sum| {
            const strategy = self.allocator.alloc(f32, strat_sum.len) catch return null;
            
            var normalizing_sum: f32 = 0.0;
            for (strat_sum) |s| {
                normalizing_sum += s;
            }
            
            if (normalizing_sum > 0) {
                for (strat_sum, 0..) |s, i| {
                    strategy[i] = s / normalizing_sum;
                }
            } else {
                const uniform = 1.0 / @as(f32, @floatFromInt(strat_sum.len));
                for (strategy) |*s| {
                    s.* = uniform;
                }
            }
            
            return strategy;
        }
        
        return null;
    }
};

test "kuhn poker cfr convergence" {
    const allocator = testing.allocator;
    
    var cfr_trainer = KuhnCFR.init(allocator);
    defer cfr_trainer.deinit();
    
    // Train for 10000 iterations
    try cfr_trainer.train(10000);
    
    // Check convergence to Nash equilibrium
    // Known Nash equilibrium strategies for Kuhn Poker:
    // Jack: always pass, fold to bet
    // Queen: pass first, call bet 1/3 of time
    // King: bet 3/alpha of time first (alpha ≈ 3), always call
    
    // Test Player 1 with Jack
    const j_strat = cfr_trainer.getAverageStrategy("J");
    if (j_strat) |strat| {
        defer allocator.free(strat);
        // Should mostly pass with Jack
        try testing.expect(strat[0] > 0.8); // Pass probability > 0.8
    }
    
    // Test Player 1 with King  
    const k_strat = cfr_trainer.getAverageStrategy("K");
    if (k_strat) |strat| {
        defer allocator.free(strat);
        // Should bet about 1/3 of time with King
        try testing.expect(strat[1] > 0.2 and strat[1] < 0.5);
    }
    
    // Test Player 2 with Queen after bet
    const qb_strat = cfr_trainer.getAverageStrategy("Qb");
    if (qb_strat) |strat| {
        defer allocator.free(strat);
        // Should call about 1/3 of time
        try testing.expect(strat[1] > 0.2 and strat[1] < 0.5);
    }
    
    std.log.info("Kuhn Poker CFR converged successfully", .{});
}

test "mccfr initialization and basic training" {
    const allocator = testing.allocator;
    
    // Initialize MCCFR components
    var regret_tbl = try poker_ai.regret_table.RegretTable.init(allocator);
    defer regret_tbl.deinit();
    
    var strategy_agg = try poker_ai.strategy_aggregator.StrategyAggregator.init(allocator);
    defer strategy_agg.deinit();
    
    var sampler = try poker_ai.monte_carlo_sampler.MonteCarloSampler.init(
        allocator,
        poker_ai.monte_carlo_sampler.SamplingConfig.default()
    );
    defer sampler.deinit();
    
    // Create MCCFR trainer
    const config = poker_ai.mccfr.MCCFRConfig{
        .iterations = 100,
        .thread_count = 2,
        .batch_size = 10,
        .use_cfr_plus = true,
    };
    
    var trainer = try poker_ai.mccfr.MCCFRTrainer.init(
        allocator,
        config,
        &regret_tbl,
        &strategy_agg,
        &sampler
    );
    defer trainer.deinit();
    
    // Run short training
    try trainer.train();
    
    // Check that training completed
    const stats = trainer.stats;
    try testing.expect(stats.total_nodes_visited.load(.monotonic) > 0);
    try testing.expect(stats.iterations_per_second > 0);
    
    // Check convergence stats
    const conv_stats = trainer.getConvergenceStats();
    try testing.expect(conv_stats.iterations_completed > 0);
}

test "information set hashing consistency" {
    const allocator = testing.allocator;
    
    var game = try poker_ai.game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    
    // Set up game state
    game.players[0].hand = poker_ai.game_state.Hand.init(0, 1); // AA
    game.players[1].hand = poker_ai.game_state.Hand.init(12, 25); // KK
    
    // Compute hash multiple times - should be consistent
    const hash1 = try poker_ai.info_set.computeInfoSetHash(&game, 0);
    const hash2 = try poker_ai.info_set.computeInfoSetHash(&game, 0);
    
    try testing.expectEqual(hash1, hash2);
    
    // Different players should have different hashes
    const hash3 = try poker_ai.info_set.computeInfoSetHash(&game, 1);
    try testing.expect(hash1 != hash3);
}

test "regret table operations" {
    const allocator = testing.allocator;
    
    var table = try poker_ai.regret_table.RegretTable.init(allocator);
    defer table.deinit();
    
    // Create and update entries
    const hash1: u64 = 0x1234567890ABCDEF;
    const entry1 = try table.getOrCreate(hash1);
    
    try testing.expectEqual(@as(u8, 3), entry1.num_actions);
    try testing.expectEqual(@as(u32, 1), entry1.visit_count);
    
    // Update regrets
    entry1.regrets[0] = 10.0;
    entry1.regrets[1] = -5.0;
    entry1.regrets[2] = 3.0;
    
    // Get positive regrets
    const positive = try entry1.getPositiveRegrets(allocator);
    defer allocator.free(positive);
    
    try testing.expectEqual(@as(f32, 10.0), positive[0]);
    try testing.expectEqual(@as(f32, 0.0), positive[1]);
    try testing.expectEqual(@as(f32, 3.0), positive[2]);
}

test "strategy aggregation and averaging" {
    const allocator = testing.allocator;
    
    var aggregator = try poker_ai.strategy_aggregator.StrategyAggregator.init(allocator);
    defer aggregator.deinit();
    
    const hash: u64 = 0xFEDCBA0987654321;
    const strategy1 = [_]f32{ 0.5, 0.3, 0.2 };
    const strategy2 = [_]f32{ 0.4, 0.4, 0.2 };
    
    // Update strategies with different weights
    try aggregator.updateStrategy(hash, &strategy1, 1.0);
    try aggregator.updateStrategy(hash, &strategy2, 2.0);
    
    // Get average strategy
    var output: [3]f32 = undefined;
    const found = try aggregator.getAverageStrategy(hash, &output);
    
    try testing.expect(found);
    
    // Expected average: (1*[0.5,0.3,0.2] + 2*[0.4,0.4,0.2]) / 3
    // = ([0.5,0.3,0.2] + [0.8,0.8,0.4]) / 3
    // = [1.3,1.1,0.6] / 3
    // = [0.433,0.367,0.2]
    try testing.expectApproxEqAbs(@as(f32, 0.433), output[0], 0.01);
    try testing.expectApproxEqAbs(@as(f32, 0.367), output[1], 0.01);
    try testing.expectApproxEqAbs(@as(f32, 0.2), output[2], 0.01);
}

test "monte carlo sampling with variance reduction" {
    const allocator = testing.allocator;
    
    var config = poker_ai.monte_carlo_sampler.SamplingConfig.lowVariance();
    var sampler = try poker_ai.monte_carlo_sampler.MonteCarloSampler.init(allocator, config);
    defer sampler.deinit();
    
    // Test baseline updates
    const info_set_hash: u64 = 0x1111222233334444;
    
    try sampler.updateBaseline(info_set_hash, 10.0);
    try sampler.updateBaseline(info_set_hash, 12.0);
    try sampler.updateBaseline(info_set_hash, 8.0);
    
    const baseline = sampler.getBaseline(info_set_hash);
    try testing.expect(baseline > 0.0);
    
    // Test variance reduction
    const reduced = sampler.applyVarianceReduction(info_set_hash, 15.0);
    try testing.expect(@abs(reduced) < 15.0);
    
    // Check statistics
    const stats = sampler.getStats();
    try testing.expectEqual(@as(u64, 0), stats.total_samples); // No games sampled yet
    try testing.expectEqual(@as(usize, 1), stats.unique_states);
}