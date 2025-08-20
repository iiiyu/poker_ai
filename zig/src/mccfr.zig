// Monte Carlo Counterfactual Regret Minimization (MCCFR)
// High-performance implementation with SIMD optimizations and parallel traversal

const std = @import("std");
const builtin = @import("builtin");
const game_state = @import("game_state.zig");
const info_set = @import("info_set.zig");
const regret_table = @import("regret_table.zig");
const strategy_aggregator = @import("strategy_aggregator.zig");
const monte_carlo_sampler = @import("monte_carlo_sampler.zig");

// MCCFR Configuration
pub const MCCFRConfig = struct {
    iterations: u32 = 10000,
    exploration_epsilon: f32 = 0.6,
    pruning_threshold: f32 = -300.0,
    discount_factor: f32 = 0.95,
    thread_count: u32 = 8,
    batch_size: u32 = 100,
    use_cfr_plus: bool = true,
    variance_reduction: bool = true,
    
    pub fn default() MCCFRConfig {
        return .{};
    }
    
    pub fn highPerformance() MCCFRConfig {
        return .{
            .iterations = 100000,
            .thread_count = @intCast(std.Thread.getCpuCount() catch 8),
            .batch_size = 500,
            .use_cfr_plus = true,
            .variance_reduction = true,
        };
    }
};

// MCCFR Algorithm State
pub const MCCFRState = struct {
    iteration: u32,
    epsilon: f32,
    temperature: f32,
    
    pub fn init() MCCFRState {
        return .{
            .iteration = 0,
            .epsilon = 1.0,
            .temperature = 1.0,
        };
    }
    
    pub fn updateEpsilon(self: *MCCFRState, config: MCCFRConfig) void {
        // Decay exploration over time
        const decay_rate = 0.99995;
        self.epsilon = @max(config.exploration_epsilon, self.epsilon * decay_rate);
    }
};

// Main MCCFR Trainer
pub const MCCFRTrainer = struct {
    config: MCCFRConfig,
    state: MCCFRState,
    regret_table: *regret_table.RegretTable,
    strategy_agg: *strategy_aggregator.StrategyAggregator,
    sampler: *monte_carlo_sampler.MonteCarloSampler,
    
    // Thread-local storage for parallel workers
    thread_locals: []ThreadLocalData,
    
    // Memory pools
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    
    // Statistics
    stats: TrainingStats,
    
    const Self = @This();
    
    pub const ThreadLocalData = struct {
        scratch_buffer: []align(64) u8,
        local_regrets: std.ArrayList(f32),
        rng: std.Random.DefaultPrng,
        iteration_count: u32,
    };
    
    pub const TrainingStats = struct {
        total_nodes_visited: std.atomic.Value(u64),
        total_time_ms: std.atomic.Value(u64),
        iterations_per_second: f64,
        convergence_rate: f32,
        
        pub fn init() TrainingStats {
            return .{
                .total_nodes_visited = std.atomic.Value(u64).init(0),
                .total_time_ms = std.atomic.Value(u64).init(0),
                .iterations_per_second = 0.0,
                .convergence_rate = 0.0,
            };
        }
    };
    
    pub fn init(
        allocator: std.mem.Allocator,
        config: MCCFRConfig,
        regret_table_ptr: *regret_table.RegretTable,
        strategy_agg_ptr: *strategy_aggregator.StrategyAggregator,
        sampler_ptr: *monte_carlo_sampler.MonteCarloSampler,
    ) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        
        // Initialize thread-local storage
        const thread_locals = try arena_allocator.alloc(ThreadLocalData, config.thread_count);
        for (thread_locals) |*tls| {
            tls.* = .{
                .scratch_buffer = try arena_allocator.alignedAlloc(u8, 64, 4096),
                .local_regrets = std.ArrayList(f32).init(arena_allocator),
                .rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
                .iteration_count = 0,
            };
        }
        
        return Self{
            .config = config,
            .state = MCCFRState.init(),
            .regret_table = regret_table_ptr,
            .strategy_agg = strategy_agg_ptr,
            .sampler = sampler_ptr,
            .thread_locals = thread_locals,
            .arena = arena,
            .allocator = allocator,
            .stats = TrainingStats.init(),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }
    
    // Main training loop
    pub fn train(self: *Self) !void {
        const start_time = std.time.milliTimestamp();
        std.log.info("Starting MCCFR training with {} threads", .{self.config.thread_count});
        
        // Create thread pool
        const threads = try self.allocator.alloc(std.Thread, self.config.thread_count);
        defer self.allocator.free(threads);
        
        // Launch worker threads
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThread, .{ self, i });
        }
        
        // Wait for completion
        for (threads) |thread| {
            thread.join();
        }
        
        // Calculate statistics
        const end_time = std.time.milliTimestamp();
        const total_ms = @as(u64, @intCast(end_time - start_time));
        _ = self.stats.total_time_ms.swap(total_ms, .monotonic);
        
        const total_iterations = self.config.iterations * self.config.thread_count;
        self.stats.iterations_per_second = @as(f64, @floatFromInt(total_iterations)) / 
                                          (@as(f64, @floatFromInt(total_ms)) / 1000.0);
        
        std.log.info("Training completed: {} iterations/second", .{self.stats.iterations_per_second});
    }
    
    // Worker thread function
    fn workerThread(self: *Self, thread_id: usize) !void {
        var tls = &self.thread_locals[thread_id];
        const iterations_per_thread = self.config.iterations / self.config.thread_count;
        
        var iter: u32 = 0;
        while (iter < iterations_per_thread) : (iter += 1) {
            // Run batch of iterations
            var batch: u32 = 0;
            while (batch < self.config.batch_size and iter + batch < iterations_per_thread) : (batch += 1) {
                try self.runIteration(tls);
                tls.iteration_count += 1;
            }
            
            // Periodic synchronization
            if (iter % 1000 == 0) {
                self.state.updateEpsilon(self.config);
                _ = self.stats.total_nodes_visited.fetchAdd(1000, .monotonic);
            }
        }
    }
    
    // Single iteration of MCCFR
    fn runIteration(self: *Self, tls: *ThreadLocalData) !void {
        // Sample game instance
        var game = try self.sampler.sampleGame(tls.rng.random());
        defer game.deinit();
        
        // Run MCCFR for each player
        for (0..game.num_players) |player| {
            if (self.config.use_cfr_plus) {
                _ = try self.cfrPlus(&game, @intCast(player), 1.0, 1.0, tls);
            } else {
                _ = try self.cfr(&game, @intCast(player), 1.0, 1.0, tls);
            }
        }
    }
    
    // Standard CFR traversal
    fn cfr(
        self: *Self,
        game: *game_state.GameState,
        player: u8,
        pi_0: f32,
        pi_1: f32,
        tls: *ThreadLocalData,
    ) !f32 {
        if (game.isTerminal()) {
            return self.evaluateTerminal(game, player);
        }
        
        const current_player = game.current_player;
        const info_set_hash = try info_set.computeInfoSetHash(game, current_player);
        
        // Get or create regret entry
        const entry = try self.regret_table.getOrCreate(info_set_hash);
        
        // Calculate strategy using regret matching
        const strategy = try self.calculateStrategy(entry, tls);
        defer tls.local_regrets.shrinkRetainingCapacity(0);
        
        const actions = try self.sampler.getAvailableActions(game);
        defer self.allocator.free(actions);
        
        var utilities = try tls.local_regrets.addManyAsArray(actions.len);
        var node_utility: f32 = 0.0;
        
        // Traverse each action
        for (actions, 0..) |action, i| {
            var next_game = try game.clone();
            defer next_game.deinit();
            
            try next_game.applyAction(action);
            
            const new_pi_0 = if (current_player == 0) pi_0 * strategy[i] else pi_0;
            const new_pi_1 = if (current_player == 1) pi_1 * strategy[i] else pi_1;
            
            utilities[i] = try self.cfr(&next_game, player, new_pi_0, new_pi_1, tls);
            node_utility += strategy[i] * utilities[i];
        }
        
        // Update regrets for acting player
        if (current_player == player) {
            const counterfactual_reach = if (player == 0) pi_1 else pi_0;
            try self.updateRegrets(entry, utilities, node_utility, counterfactual_reach);
        }
        
        return node_utility;
    }
    
    // CFR+ with pruning
    fn cfrPlus(
        self: *Self,
        game: *game_state.GameState,
        player: u8,
        pi_0: f32,
        pi_1: f32,
        tls: *ThreadLocalData,
    ) !f32 {
        if (game.isTerminal()) {
            return self.evaluateTerminal(game, player);
        }
        
        const current_player = game.current_player;
        const info_set_hash = try info_set.computeInfoSetHash(game, current_player);
        
        // Get or create regret entry
        const entry = try self.regret_table.getOrCreate(info_set_hash);
        
        // Check for pruning
        if (self.shouldPrune(entry)) {
            return 0.0;
        }
        
        // Calculate strategy using regret matching plus
        const strategy = try self.calculateStrategyPlus(entry, tls);
        defer tls.local_regrets.shrinkRetainingCapacity(0);
        
        const actions = try self.sampler.getAvailableActions(game);
        defer self.allocator.free(actions);
        
        var utilities = try tls.local_regrets.addManyAsArray(actions.len);
        var node_utility: f32 = 0.0;
        
        // Traverse each action (with pruning)
        for (actions, 0..) |action, i| {
            // Skip pruned actions
            if (entry.regrets[i] < self.config.pruning_threshold) {
                utilities[i] = 0.0;
                continue;
            }
            
            var next_game = try game.clone();
            defer next_game.deinit();
            
            try next_game.applyAction(action);
            
            const new_pi_0 = if (current_player == 0) pi_0 * strategy[i] else pi_0;
            const new_pi_1 = if (current_player == 1) pi_1 * strategy[i] else pi_1;
            
            utilities[i] = try self.cfrPlus(&next_game, player, new_pi_0, new_pi_1, tls);
            node_utility += strategy[i] * utilities[i];
        }
        
        // Update regrets with CFR+ rule (max with 0)
        if (current_player == player) {
            const counterfactual_reach = if (player == 0) pi_1 else pi_0;
            try self.updateRegretsPlus(entry, utilities, node_utility, counterfactual_reach);
        }
        
        // Update average strategy
        if (current_player == player) {
            const reach_prob = if (player == 0) pi_0 else pi_1;
            try self.strategy_agg.updateStrategy(info_set_hash, strategy, reach_prob);
        }
        
        return node_utility;
    }
    
    // Calculate strategy from regrets using regret matching
    fn calculateStrategy(self: *Self, entry: *regret_table.RegretEntry, tls: *ThreadLocalData) ![]f32 {
        _ = self;
        const num_actions = entry.num_actions;
        var strategy = try tls.local_regrets.addManyAsArray(num_actions);
        
        var sum: f32 = 0.0;
        
        // SIMD-optimized regret matching
        if (builtin.cpu.arch == .x86_64 and num_actions >= 4) {
            // Use SIMD for calculating positive regrets
            var i: usize = 0;
            while (i + 4 <= num_actions) : (i += 4) {
                const regrets = @as(@Vector(4, f32), entry.regrets[i..][0..4].*);
                const positive = @max(regrets, @as(@Vector(4, f32), @splat(0.0)));
                strategy[i..][0..4].* = positive;
                sum += @reduce(.Add, positive);
            }
            // Handle remaining elements
            while (i < num_actions) : (i += 1) {
                strategy[i] = @max(0.0, entry.regrets[i]);
                sum += strategy[i];
            }
        } else {
            // Scalar fallback
            for (entry.regrets[0..num_actions], 0..) |regret, i| {
                strategy[i] = @max(0.0, regret);
                sum += strategy[i];
            }
        }
        
        // Normalize to probability distribution
        if (sum > 0.0) {
            const inv_sum = 1.0 / sum;
            for (strategy[0..num_actions]) |*prob| {
                prob.* *= inv_sum;
            }
        } else {
            // Uniform distribution if no positive regrets
            const uniform = 1.0 / @as(f32, @floatFromInt(num_actions));
            for (strategy[0..num_actions]) |*prob| {
                prob.* = uniform;
            }
        }
        
        return strategy[0..num_actions];
    }
    
    // Calculate strategy for CFR+
    fn calculateStrategyPlus(self: *Self, entry: *regret_table.RegretEntry, tls: *ThreadLocalData) ![]f32 {
        return self.calculateStrategy(entry, tls);
    }
    
    // Update regrets with SIMD optimization
    fn updateRegrets(
        self: *Self,
        entry: *regret_table.RegretEntry,
        utilities: []f32,
        node_utility: f32,
        counterfactual_reach: f32,
    ) !void {
        _ = self;
        const num_actions = entry.num_actions;
        
        // SIMD-optimized regret update
        if (builtin.cpu.arch == .x86_64 and num_actions >= 4) {
            const node_util_vec = @as(@Vector(4, f32), @splat(node_utility));
            const cf_reach_vec = @as(@Vector(4, f32), @splat(counterfactual_reach));
            
            var i: usize = 0;
            while (i + 4 <= num_actions) : (i += 4) {
                const utils = @as(@Vector(4, f32), utilities[i..][0..4].*);
                const regret_delta = (utils - node_util_vec) * cf_reach_vec;
                const old_regrets = @as(@Vector(4, f32), entry.regrets[i..][0..4].*);
                entry.regrets[i..][0..4].* = old_regrets + regret_delta;
            }
            
            // Handle remaining elements
            while (i < num_actions) : (i += 1) {
                const regret = (utilities[i] - node_utility) * counterfactual_reach;
                entry.regrets[i] += regret;
            }
        } else {
            // Scalar fallback
            for (utilities[0..num_actions], 0..) |utility, i| {
                const regret = (utility - node_utility) * counterfactual_reach;
                entry.regrets[i] += regret;
            }
        }
    }
    
    // Update regrets for CFR+ (with max(0, regret))
    fn updateRegretsPlus(
        self: *Self,
        entry: *regret_table.RegretEntry,
        utilities: []f32,
        node_utility: f32,
        counterfactual_reach: f32,
    ) !void {
        _ = self;
        const num_actions = entry.num_actions;
        
        for (utilities[0..num_actions], 0..) |utility, i| {
            const regret = (utility - node_utility) * counterfactual_reach;
            entry.regrets[i] = @max(0.0, entry.regrets[i] + regret);
        }
    }
    
    // Evaluate terminal node
    fn evaluateTerminal(self: *Self, game: *game_state.GameState, player: u8) f32 {
        _ = self;
        return game.getUtility(player);
    }
    
    // Check if should prune this branch
    fn shouldPrune(self: *Self, entry: *regret_table.RegretEntry) bool {
        // Check if all regrets are below pruning threshold
        for (entry.regrets[0..entry.num_actions]) |regret| {
            if (regret >= self.config.pruning_threshold) {
                return false;
            }
        }
        return true;
    }
    
    // Get convergence statistics
    pub fn getConvergenceStats(self: *Self) ConvergenceStats {
        return .{
            .iterations_completed = self.state.iteration,
            .average_regret = self.regret_table.getAverageRegret(),
            .exploitability = self.calculateExploitability(),
            .nash_distance = self.calculateNashDistance(),
        };
    }
    
    pub const ConvergenceStats = struct {
        iterations_completed: u32,
        average_regret: f32,
        exploitability: f32,
        nash_distance: f32,
    };
    
    fn calculateExploitability(self: *Self) f32 {
        _ = self;
        // Placeholder - would calculate actual exploitability
        return 0.0;
    }
    
    fn calculateNashDistance(self: *Self) f32 {
        _ = self;
        // Placeholder - would calculate distance to Nash equilibrium
        return 0.0;
    }
};

// Test MCCFR configuration
test "mccfr config initialization" {
    const testing = std.testing;
    
    const config = MCCFRConfig.default();
    try testing.expectEqual(@as(u32, 10000), config.iterations);
    try testing.expectEqual(@as(f32, 0.6), config.exploration_epsilon);
    
    const hp_config = MCCFRConfig.highPerformance();
    try testing.expectEqual(@as(u32, 100000), hp_config.iterations);
    try testing.expect(hp_config.thread_count > 0);
}

// Test MCCFR state
test "mccfr state updates" {
    const testing = std.testing;
    
    var state = MCCFRState.init();
    try testing.expectEqual(@as(u32, 0), state.iteration);
    try testing.expectEqual(@as(f32, 1.0), state.epsilon);
    
    const config = MCCFRConfig.default();
    state.updateEpsilon(config);
    try testing.expect(state.epsilon <= 1.0);
}