// Monte Carlo Sampling for MCCFR
// Efficient sampling with variance reduction techniques

const std = @import("std");
const game_state = @import("game_state.zig");

// Sampling configuration
pub const SamplingConfig = struct {
    epsilon_exploration: f32 = 0.6,
    outcome_sampling: bool = true,
    external_sampling: bool = false,
    chance_sampling: bool = true,
    importance_sampling: bool = true,
    baseline_correction: bool = true,

    pub fn default() SamplingConfig {
        return .{};
    }

    pub fn lowVariance() SamplingConfig {
        return .{
            .epsilon_exploration = 0.3,
            .outcome_sampling = false,
            .external_sampling = true,
            .importance_sampling = true,
            .baseline_correction = true,
        };
    }
};

// Monte Carlo sampler with variance reduction
pub const MonteCarloSampler = struct {
    config: SamplingConfig,
    allocator: std.mem.Allocator,

    // Variance reduction state
    baseline_values: std.HashMap(u64, f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    sample_counts: std.HashMap(u64, u32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),

    // Statistics
    total_samples: u64,
    variance_estimate: f64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: SamplingConfig) !Self {
        return Self{
            .config = config,
            .allocator = allocator,
            .baseline_values = std.HashMap(u64, f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .sample_counts = std.HashMap(u64, u32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .total_samples = 0,
            .variance_estimate = 0.0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.baseline_values.deinit();
        self.sample_counts.deinit();
    }

    // Sample a game instance
    pub fn sampleGame(self: *Self, rng: std.Random) !game_state.GameState {
        const num_players = 2; // Texas Hold'em heads-up
        const small_blind = 5;
        const big_blind = 10;

        var game = try game_state.GameState.init(self.allocator, num_players, small_blind, big_blind);

        // Sample starting stacks
        const stack_sizes = [_]u32{ 1000, 1500, 2000 };
        const stack_idx = rng.uintLessThan(usize, stack_sizes.len);
        for (&game.players) |*player| {
            player.stack = stack_sizes[stack_idx];
        }

        // Sample hole cards
        const deck = try self.createShuffledDeck(rng);
        defer self.allocator.free(deck);

        game.players[0].hand = game_state.Hand.init(deck[0], deck[1]);
        game.players[1].hand = game_state.Hand.init(deck[2], deck[3]);

        // Store remaining deck for board cards
        game.deck_position = 4;

        self.total_samples += 1;

        return game;
    }

    // Create shuffled deck
    fn createShuffledDeck(self: *Self, rng: std.Random) ![]u8 {
        var deck = try self.allocator.alloc(u8, 52);
        for (0..52) |i| {
            deck[i] = @intCast(i);
        }

        // Fisher-Yates shuffle
        var i = deck.len;
        while (i > 1) {
            i -= 1;
            const j = rng.uintLessThan(usize, i + 1);
            std.mem.swap(u8, &deck[i], &deck[j]);
        }

        return deck;
    }

    // Get available actions with sampling
    pub fn getAvailableActions(self: *Self, game: *game_state.GameState) ![]game_state.Action {
        var actions = std.ArrayList(game_state.Action).init(self.allocator);

        const current_bet = game.current_bet;
        const player = &game.players[game.current_player];
        const player_bet = player.bet_this_round;
        const player_stack = player.stack;

        // Always include fold (except when checking is free)
        if (current_bet > player_bet) {
            try actions.append(game_state.Action.fold());
        }

        // Check or call
        if (current_bet == player_bet) {
            try actions.append(game_state.Action.check());
        } else {
            const call_amount = @min(current_bet - player_bet, player_stack);
            if (call_amount == player_stack) {
                try actions.append(game_state.Action.allIn(player_stack + player_bet));
            } else {
                try actions.append(game_state.Action.call());
            }
        }

        // Raise options (with abstraction)
        if (player_stack > current_bet - player_bet) {
            const min_raise = current_bet + game.big_blind;
            const max_raise = player_bet + player_stack;

            if (self.config.outcome_sampling) {
                // Sample subset of raise sizes for efficiency
                const raise_fractions = [_]f32{ 0.33, 0.5, 0.75, 1.0 };
                for (raise_fractions) |fraction| {
                    const raise_amount = @as(u32, @intFromFloat(@as(f32, @floatFromInt(game.pot)) * fraction)) + current_bet;

                    if (raise_amount >= min_raise and raise_amount <= max_raise) {
                        if (raise_amount == max_raise) {
                            try actions.append(game_state.Action.allIn(max_raise));
                        } else {
                            try actions.append(game_state.Action.raise(raise_amount));
                        }
                    }
                }
            } else {
                // Full action space
                const pot_fraction_raises = [_]f32{ 0.25, 0.33, 0.5, 0.67, 0.75, 1.0, 1.5, 2.0 };
                for (pot_fraction_raises) |fraction| {
                    const raise_amount = @as(u32, @intFromFloat(@as(f32, @floatFromInt(game.pot)) * fraction)) + current_bet;

                    if (raise_amount >= min_raise and raise_amount < max_raise) {
                        try actions.append(game_state.Action.raise(raise_amount));
                    }
                }

                // Always include all-in as option
                if (max_raise > min_raise) {
                    try actions.append(game_state.Action.allIn(max_raise));
                }
            }
        }

        return actions.toOwnedSlice();
    }

    // Sample action with epsilon exploration
    pub fn sampleAction(
        self: *Self,
        actions: []const game_state.Action,
        strategy: []const f32,
        rng: std.Random,
    ) struct { action: game_state.Action, probability: f32 } {
        std.debug.assert(actions.len == strategy.len);

        const epsilon = self.config.epsilon_exploration;
        const explore = rng.float(f32) < epsilon;

        if (explore) {
            // Uniform exploration
            const idx = rng.uintLessThan(usize, actions.len);
            const prob = epsilon / @as(f32, @floatFromInt(actions.len)) +
                (1.0 - epsilon) * strategy[idx];
            return .{ .action = actions[idx], .probability = prob };
        } else {
            // Sample from strategy
            const sample = rng.float(f32);
            var cumulative: f32 = 0.0;

            for (actions, 0..) |action, i| {
                cumulative += strategy[i];
                if (sample <= cumulative) {
                    const prob = epsilon / @as(f32, @floatFromInt(actions.len)) +
                        (1.0 - epsilon) * strategy[i];
                    return .{ .action = action, .probability = prob };
                }
            }

            // Fallback to last action
            const last_idx = actions.len - 1;
            const prob = epsilon / @as(f32, @floatFromInt(actions.len)) +
                (1.0 - epsilon) * strategy[last_idx];
            return .{ .action = actions[last_idx], .probability = prob };
        }
    }

    // Apply importance sampling correction
    pub fn importanceSamplingWeight(
        self: *Self,
        sampled_prob: f32,
        target_prob: f32,
    ) f32 {
        if (!self.config.importance_sampling) {
            return 1.0;
        }

        if (sampled_prob <= 0.0) {
            return 0.0;
        }

        // Clip to prevent extreme weights
        const weight = target_prob / sampled_prob;
        return @min(10.0, @max(0.1, weight));
    }

    // Update baseline for variance reduction
    pub fn updateBaseline(
        self: *Self,
        info_set_hash: u64,
        value: f32,
    ) !void {
        if (!self.config.baseline_correction) {
            return;
        }

        const count_entry = try self.sample_counts.getOrPut(info_set_hash);
        if (!count_entry.found_existing) {
            count_entry.value_ptr.* = 0;
        }
        count_entry.value_ptr.* += 1;

        const baseline_entry = try self.baseline_values.getOrPut(info_set_hash);
        if (!baseline_entry.found_existing) {
            baseline_entry.value_ptr.* = value;
        } else {
            // Exponential moving average
            const alpha: f32 = 0.1;
            baseline_entry.value_ptr.* = alpha * value + (1.0 - alpha) * baseline_entry.value_ptr.*;
        }

        // Update variance estimate
        const baseline = baseline_entry.value_ptr.*;
        const diff = value - baseline;
        self.variance_estimate = 0.99 * self.variance_estimate + 0.01 * diff * diff;
    }

    // Get baseline value for variance reduction
    pub fn getBaseline(self: *Self, info_set_hash: u64) f32 {
        if (!self.config.baseline_correction) {
            return 0.0;
        }

        if (self.baseline_values.get(info_set_hash)) |baseline| {
            return baseline;
        }

        return 0.0;
    }

    // Apply variance reduction to value
    pub fn applyVarianceReduction(
        self: *Self,
        info_set_hash: u64,
        raw_value: f32,
    ) f32 {
        if (!self.config.baseline_correction) {
            return raw_value;
        }

        const baseline = self.getBaseline(info_set_hash);
        return raw_value - baseline;
    }

    // Get sampling statistics
    pub fn getStats(self: *Self) SamplingStats {
        var total_baselines: u64 = 0;
        var avg_samples_per_state: f32 = 0.0;

        if (self.sample_counts.count() > 0) {
            var iterator = self.sample_counts.iterator();
            while (iterator.next()) |entry| {
                total_baselines += entry.value_ptr.*;
            }
            avg_samples_per_state = @as(f32, @floatFromInt(total_baselines)) /
                @as(f32, @floatFromInt(self.sample_counts.count()));
        }

        return .{
            .total_samples = self.total_samples,
            .unique_states = self.sample_counts.count(),
            .avg_samples_per_state = avg_samples_per_state,
            .variance_estimate = @floatCast(self.variance_estimate),
        };
    }

    pub const SamplingStats = struct {
        total_samples: u64,
        unique_states: usize,
        avg_samples_per_state: f32,
        variance_estimate: f32,
    };
};

// Advanced sampling techniques
pub const AdvancedSampler = struct {
    base_sampler: MonteCarloSampler,

    // Stratified sampling state
    strata: std.ArrayList(Stratum),
    current_stratum: usize,

    // Control variates
    control_variates: std.HashMap(u64, f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),

    allocator: std.mem.Allocator,

    const Self = @This();

    pub const Stratum = struct {
        id: u32,
        weight: f32,
        samples: u32,
        value_sum: f64,
    };

    pub fn init(allocator: std.mem.Allocator, config: SamplingConfig) !Self {
        return Self{
            .base_sampler = try MonteCarloSampler.init(allocator, config),
            .strata = std.ArrayList(Stratum).init(allocator),
            .current_stratum = 0,
            .control_variates = std.HashMap(u64, f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base_sampler.deinit();
        self.strata.deinit();
        self.control_variates.deinit();
    }

    // Initialize strata for stratified sampling
    pub fn initializeStrata(self: *Self, num_strata: u32) !void {
        self.strata.clearRetainingCapacity();

        const uniform_weight = 1.0 / @as(f32, @floatFromInt(num_strata));
        for (0..num_strata) |i| {
            try self.strata.append(.{
                .id = @intCast(i),
                .weight = uniform_weight,
                .samples = 0,
                .value_sum = 0.0,
            });
        }
    }

    // Select next stratum for sampling
    pub fn selectStratum(self: *Self, rng: std.Random) *Stratum {
        if (self.strata.items.len == 0) {
            return undefined; // Should initialize strata first
        }

        // Weighted selection based on stratum weights
        const r = rng.float(f32);
        var cumulative: f32 = 0.0;

        for (self.strata.items) |*stratum| {
            cumulative += stratum.weight;
            if (r <= cumulative) {
                return stratum;
            }
        }

        return &self.strata.items[self.strata.items.len - 1];
    }

    // Update stratum weights based on variance
    pub fn updateStrataWeights(self: *Self) void {
        if (self.strata.items.len == 0) return;

        var total_variance: f64 = 0.0;

        // Calculate variance for each stratum
        for (self.strata.items) |*stratum| {
            if (stratum.samples > 1) {
                const mean = stratum.value_sum / @as(f64, @floatFromInt(stratum.samples));
                // Simplified variance calculation (would need to track sum of squares)
                const variance = @abs(mean) * @sqrt(@as(f64, @floatFromInt(stratum.samples)));
                total_variance += variance * stratum.weight;
            }
        }

        // Update weights proportional to standard deviation
        if (total_variance > 0) {
            for (self.strata.items) |*stratum| {
                if (stratum.samples > 0) {
                    const mean = stratum.value_sum / @as(f64, @floatFromInt(stratum.samples));
                    const std_dev = @sqrt(@abs(mean));
                    stratum.weight = @floatCast(std_dev / total_variance);
                }
            }
        }

        // Normalize weights
        var weight_sum: f32 = 0.0;
        for (self.strata.items) |stratum| {
            weight_sum += stratum.weight;
        }

        if (weight_sum > 0) {
            for (self.strata.items) |*stratum| {
                stratum.weight /= weight_sum;
            }
        }
    }

    // Apply control variate correction
    pub fn controlVariateCorrection(
        self: *Self,
        info_set_hash: u64,
        raw_value: f32,
        control_value: f32,
    ) !f32 {
        const entry = try self.control_variates.getOrPut(info_set_hash);

        if (!entry.found_existing) {
            entry.value_ptr.* = control_value;
            return raw_value;
        }

        const expected_control = entry.value_ptr.*;
        const beta: f32 = -1.0; // Optimal beta would be -Cov(X,Y)/Var(Y)

        return raw_value + beta * (control_value - expected_control);
    }
};

// Test Monte Carlo sampler
test "monte carlo sampler initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = SamplingConfig.default();
    var sampler = try MonteCarloSampler.init(allocator, config);
    defer sampler.deinit();

    try testing.expectEqual(@as(u64, 0), sampler.total_samples);
    try testing.expectEqual(@as(f64, 0.0), sampler.variance_estimate);
}

// Test game sampling
test "sample game creation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = SamplingConfig.default();
    var sampler = try MonteCarloSampler.init(allocator, config);
    defer sampler.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    var game = try sampler.sampleGame(rng);
    defer game.deinit();

    try testing.expectEqual(@as(u8, 2), game.num_players);
    try testing.expect(!game.players[0].hand.isEmpty());
    try testing.expect(!game.players[1].hand.isEmpty());
    try testing.expectEqual(@as(u64, 1), sampler.total_samples);
}

// Test action sampling
test "action sampling with exploration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = SamplingConfig.default();
    config.epsilon_exploration = 0.1;

    var sampler = try MonteCarloSampler.init(allocator, config);
    defer sampler.deinit();

    const actions = [_]game_state.Action{
        game_state.Action.fold(),
        game_state.Action.call(),
        game_state.Action.raise(100),
    };

    const strategy = [_]f32{ 0.2, 0.5, 0.3 };

    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    const result = sampler.sampleAction(&actions, &strategy, rng);
    try testing.expect(result.probability > 0.0);
    try testing.expect(result.probability <= 1.0);
}

// Test variance reduction
test "baseline variance reduction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = SamplingConfig.default();
    config.baseline_correction = true;

    var sampler = try MonteCarloSampler.init(allocator, config);
    defer sampler.deinit();

    const info_set_hash: u64 = 0x123456789ABCDEF0;

    // Update baseline multiple times
    try sampler.updateBaseline(info_set_hash, 10.0);
    try sampler.updateBaseline(info_set_hash, 12.0);
    try sampler.updateBaseline(info_set_hash, 11.0);

    const baseline = sampler.getBaseline(info_set_hash);
    try testing.expect(baseline > 0.0);

    // Apply variance reduction
    const reduced = sampler.applyVarianceReduction(info_set_hash, 15.0);
    try testing.expect(@abs(reduced) < 15.0);
}

// Test advanced sampler strata
test "stratified sampling initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = SamplingConfig.default();
    var sampler = try AdvancedSampler.init(allocator, config);
    defer sampler.deinit();

    try sampler.initializeStrata(4);
    try testing.expectEqual(@as(usize, 4), sampler.strata.items.len);

    for (sampler.strata.items) |stratum| {
        try testing.expectApproxEqAbs(@as(f32, 0.25), stratum.weight, 0.001);
    }
}
