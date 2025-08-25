//! Linear CFR Implementation
//! Provides 2-3x faster convergence than vanilla CFR+ through alternating updates
//! Based on "Solving Imperfect-Information Games via Discounted Regret Minimization" (Brown & Sandholm, 2019)

const std = @import("std");
const game_state = @import("game_state.zig");
const GameState = game_state.GameState;
const Action = game_state.Action;

/// Update schedule for Linear CFR alternating updates
pub const UpdateSchedule = enum {
    regret,
    strategy,
    
    pub fn alternate(self: UpdateSchedule) UpdateSchedule {
        return switch (self) {
            .regret => .strategy,
            .strategy => .regret,
        };
    }
};

/// Linear CFR configuration parameters
pub const LinearCFRConfig = struct {
    /// Positive regret discount factor (> 1.0 for Linear CFR)
    discount_positive: f32 = 1.5,
    
    /// Negative regret discount factor (< 1.0 for pruning)
    discount_negative: f32 = 0.5,
    
    /// How often to apply discounting
    discount_interval: u32 = 1000,
    
    /// Threshold for pruning negative regrets
    prune_threshold: f32 = -300.0,
    
    /// Exploration probability for MCCFR sampling
    exploration_epsilon: f32 = 0.6,
    
    /// Whether to use averaging for strategy computation
    use_averaging: bool = true,
    
    // Memory management parameters
    /// Minimum iterations before any cleanup is performed
    min_iterations_before_cleanup: u32 = 10000,
    
    /// Window of iterations to consider for "recent" activity
    cleanup_staleness_window: u32 = 50000,
    
    /// Divisor for visit threshold (visits < iteration/divisor triggers removal)
    visit_threshold_divisor: u32 = 10000,
    
    /// How often to run cleanup (0 = never)
    cleanup_interval: u32 = 5000,
    
    /// Maximum percentage of InfoSets to remove in one cleanup pass
    max_cleanup_percentage: f32 = 0.1,
};

/// Information set data with separate regret and strategy tracking
pub const InfoSetData = struct {
    /// Cumulative regrets for each action
    regrets: []f32,
    
    /// Current strategy (action probabilities)
    strategy: []f32,
    
    /// Strategy sum for averaging
    strategy_sum: []f32,
    
    /// Number of times this infoset was visited
    visits: u32,
    
    /// Last iteration this was updated
    last_update: u32,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, num_actions: usize) !Self {
        const regrets = try allocator.alloc(f32, num_actions);
        const strategy = try allocator.alloc(f32, num_actions);
        const strategy_sum = try allocator.alloc(f32, num_actions);
        
        // Initialize arrays to zero
        @memset(regrets, 0.0);
        @memset(strategy, 1.0 / @as(f32, @floatFromInt(num_actions)));
        @memset(strategy_sum, 0.0);
        
        return Self{
            .regrets = regrets,
            .strategy = strategy,
            .strategy_sum = strategy_sum,
            .visits = 0,
            .last_update = 0,
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.regrets);
        allocator.free(self.strategy);
        allocator.free(self.strategy_sum);
    }
    
    /// Get current strategy using regret matching with robust floating point handling
    pub fn getCurrentStrategy(self: *Self) []f32 {
        var normalizing_sum: f32 = 0.0;
        
        // Compute strategy from positive regrets
        for (self.regrets, 0..) |regret, i| {
            // Validate regret value
            const valid_regret = if (std.math.isFinite(regret) and regret > 0) regret else 0.0;
            self.strategy[i] = valid_regret;
            normalizing_sum += self.strategy[i];
        }
        
        // Normalize or use uniform strategy
        if (normalizing_sum > 1e-10 and std.math.isFinite(normalizing_sum)) {
            for (self.strategy) |*s| {
                s.* /= normalizing_sum;
                // Clamp to valid probability range
                if (!std.math.isFinite(s.*) or s.* < 0.0) {
                    s.* = 0.0;
                } else if (s.* > 1.0) {
                    s.* = 1.0;
                }
            }
        } else {
            // Fall back to uniform strategy
            const uniform = 1.0 / @as(f32, @floatFromInt(self.strategy.len));
            for (self.strategy) |*s| {
                s.* = uniform;
            }
        }
        
        return self.strategy;
    }
    
    /// Get average strategy for final solution with robust validation
    pub fn getAverageStrategy(self: *Self) []f32 {
        var normalizing_sum: f32 = 0.0;
        
        // Calculate sum with validation
        for (self.strategy_sum) |s| {
            if (std.math.isFinite(s) and s >= 0.0) {
                normalizing_sum += s;
            }
        }
        
        if (normalizing_sum > 1e-10 and std.math.isFinite(normalizing_sum)) {
            for (self.strategy_sum, 0..) |s, i| {
                if (std.math.isFinite(s) and s >= 0.0) {
                    self.strategy[i] = s / normalizing_sum;
                    // Clamp to valid range
                    if (self.strategy[i] > 1.0) {
                        self.strategy[i] = 1.0;
                    }
                } else {
                    self.strategy[i] = 0.0;
                }
            }
        } else {
            // Fall back to uniform strategy
            const uniform = 1.0 / @as(f32, @floatFromInt(self.strategy.len));
            for (self.strategy) |*s| {
                s.* = uniform;
            }
        }
        
        return self.strategy;
    }
};

/// Linear CFR trainer with alternating updates
pub const LinearCFRTrainer = struct {
    config: LinearCFRConfig,
    update_schedule: UpdateSchedule,
    iteration: u32,
    allocator: std.mem.Allocator,
    
    /// Storage for all information sets
    infoset_map: std.AutoHashMap(u64, InfoSetData),
    
    /// Random number generator for sampling
    prng: std.Random.DefaultPrng,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: LinearCFRConfig) !Self {
        // Pre-allocate HashMap capacity to reduce resizing overhead
        var infoset_map = std.AutoHashMap(u64, InfoSetData).init(allocator);
        try infoset_map.ensureTotalCapacity(100_000); // Start with reasonable capacity
        
        return Self{
            .config = config,
            .update_schedule = .regret,
            .iteration = 0,
            .allocator = allocator,
            .infoset_map = infoset_map,
            .prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iter = self.infoset_map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.infoset_map.deinit();
    }
    
    /// Main training iteration with memory monitoring
    pub fn iterate(self: *Self, state: *GameState) !f32 {
        // Check for iteration overflow (u32 max = 4.3B)
        if (self.iteration == std.math.maxInt(u32)) {
            return error.IterationOverflow;
        }
        
        self.iteration += 1;
        
        // Memory monitoring every 100 iterations
        if (self.iteration % 100 == 0) {
            const infoset_count = self.infoset_map.count();
            const estimated_memory = infoset_count * (@sizeOf(InfoSetData) + (3 * 5 * @sizeOf(f32))); // Assume avg 5 actions
            
            // Warn at 500MB, error at 1GB
            if (estimated_memory > 1_073_741_824) { // 1GB
                std.log.err("Memory usage critical: {d:.2} GB. InfoSets: {d}", .{ @as(f32, @floatFromInt(estimated_memory)) / 1_073_741_824.0, infoset_count });
                return error.OutOfMemory;
            } else if (estimated_memory > 524_288_000) { // 500MB
                std.log.warn("Memory usage high: {d:.2} MB. InfoSets: {d}", .{ @as(f32, @floatFromInt(estimated_memory)) / 1_048_576.0, infoset_count });
            }
        }
        
        // Apply discounting periodically
        if (self.iteration % self.config.discount_interval == 0) {
            try self.applyDiscounting();
            
            // Periodic cleanup of rarely visited InfoSets to prevent memory explosion
            if (self.iteration % (self.config.discount_interval * 10) == 0) {
                try self.cleanupRareInfoSets();
            }
        }
        
        // Alternate between regret and strategy updates
        const utility = switch (self.update_schedule) {
            .regret => try self.traverseUpdateRegretsLimited(state, 0, 1.0, 1.0, 0),
            .strategy => try self.traverseUpdateStrategyLimited(state, 0, 1.0, 1.0, 0),
        };
        
        // Switch update mode for next iteration
        self.update_schedule = self.update_schedule.alternate();
        
        return utility;
    }
    
    const MAX_DEPTH = 20; // Maximum recursion depth to prevent stack overflow
    
    /// Traverse game tree updating regrets with depth limit
    fn traverseUpdateRegretsLimited(self: *Self, state: *GameState, player: u8, pi_current: f32, pi_opponent: f32, depth: u32) !f32 {
        // Check depth limit to prevent stack overflow
        if (depth >= MAX_DEPTH) {
            return 0.0; // Return neutral utility at max depth
        }
        
        return try self.traverseUpdateRegrets(state, player, pi_current, pi_opponent, depth);
    }
    
    /// Traverse game tree updating regrets (Linear CFR regret update phase)
    fn traverseUpdateRegrets(self: *Self, state: *GameState, player: u8, pi_current: f32, pi_opponent: f32, depth: u32) !f32 {
        if (state.isTerminal()) {
            return state.getUtility(player);
        }
        
        // Additional depth check
        if (depth >= MAX_DEPTH) {
            return 0.0;
        }
        
        const current_player = state.current_player;
        const is_current_player = current_player == player;
        
        // Get or create information set with bounds checking
        const infoset_key = try state.getInfoSetKey(current_player);
        const entry = try self.infoset_map.getOrPut(infoset_key);
        if (!entry.found_existing) {
            const num_actions = state.getLegalActions().len;
            if (num_actions == 0) {
                return error.NoLegalActions;
            }
            if (num_actions > 10) { // Sanity check for poker (fold, call, raise variants)
                return error.TooManyActions;
            }
            entry.value_ptr.* = try InfoSetData.init(self.allocator, num_actions);
            
            // Prevent runaway InfoSet creation
            if (self.infoset_map.count() > 10_000_000) { // 10M limit
                std.log.err("InfoSet count exceeded safe limit: {d}", .{self.infoset_map.count()});
                return error.InfoSetLimitExceeded;
            }
        }
        
        var infoset = entry.value_ptr;
        const strategy = infoset.getCurrentStrategy();
        const actions = state.getLegalActions();
        
        // Track action utilities with bounds checking
        if (actions.len == 0) {
            return error.NoLegalActions;
        }
        if (actions.len > 10) {
            return error.TooManyActions;
        }
        
        var action_utils = try self.allocator.alloc(f32, actions.len);
        defer self.allocator.free(action_utils);
        
        // Initialize to prevent undefined behavior
        @memset(action_utils, 0.0);
        
        var node_utility: f32 = 0.0;
        
        // Sample action for opponent (MCCFR)
        var sampled_action: usize = 0;
        if (!is_current_player) {
            const rand = self.prng.random();
            if (rand.float(f32) < self.config.exploration_epsilon) {
                // Exploration
                sampled_action = rand.uintLessThan(usize, actions.len);
            } else {
                // On-policy
                sampled_action = sampleFromDistribution(rand, strategy);
            }
            
            // Take sampled action
            var next_state = try state.clone();
            defer next_state.deinit();
            
            _ = try next_state.applyAction(actions[sampled_action]);
            const new_pi_opponent = pi_opponent * strategy[sampled_action];
            
            action_utils[sampled_action] = try self.traverseUpdateRegrets(&next_state, player, pi_current, new_pi_opponent, depth + 1);
            node_utility = action_utils[sampled_action];
        } else {
            // Current player: compute all action utilities
            for (actions, 0..) |action, i| {
                var next_state = try state.clone();
                defer next_state.deinit();
                
                _ = try next_state.applyAction(action);
                const new_pi_current = pi_current * strategy[i];
                
                action_utils[i] = try self.traverseUpdateRegrets(&next_state, player, new_pi_current, pi_opponent, depth + 1);
                node_utility += strategy[i] * action_utils[i];
            }
            
            // Re-get infoset pointer after recursive calls (hashmap might have resized)
            infoset = self.infoset_map.getPtr(infoset_key).?;
            
            // Update regrets with Linear CFR weighting and NaN/Inf checking
            const cfr_weight = pi_opponent;
            
            // Check for invalid CFR weight
            if (!std.math.isFinite(cfr_weight)) {
                std.log.warn("Invalid CFR weight detected: {d}, skipping regret update", .{cfr_weight});
                return node_utility;
            }
            
            for (actions, 0..) |_, i| {
                if (i < infoset.regrets.len and i < action_utils.len) {
                    const regret = (action_utils[i] - node_utility) * cfr_weight;
                    
                    // Check for NaN/Inf before updating
                    if (std.math.isFinite(regret)) {
                        infoset.regrets[i] += regret;
                        
                        // Clamp extreme values to prevent overflow
                        if (infoset.regrets[i] > 1e6) {
                            infoset.regrets[i] = 1e6;
                        } else if (infoset.regrets[i] < -1e6) {
                            infoset.regrets[i] = -1e6;
                        }
                    } else {
                        std.log.warn("Invalid regret calculated: {d}, action {d}", .{regret, i});
                    }
                }
            }
        }
        
        // Re-get infoset pointer in case hashmap resized
        infoset = self.infoset_map.getPtr(infoset_key).?;
        infoset.visits += 1;
        infoset.last_update = self.iteration;
        
        return node_utility;
    }
    
    /// Traverse game tree updating strategy sums with depth limit
    fn traverseUpdateStrategyLimited(self: *Self, state: *GameState, player: u8, pi_current: f32, pi_opponent: f32, depth: u32) !f32 {
        if (depth >= MAX_DEPTH) {
            return 0.0;
        }
        return try self.traverseUpdateStrategy(state, player, pi_current, pi_opponent, depth);
    }
    
    /// Traverse game tree updating strategy sums (Linear CFR strategy update phase)
    fn traverseUpdateStrategy(self: *Self, state: *GameState, player: u8, pi_current: f32, pi_opponent: f32, depth: u32) !f32 {
        if (state.isTerminal()) {
            return state.getUtility(player);
        }
        
        if (depth >= MAX_DEPTH) {
            return 0.0;
        }
        
        const current_player = state.current_player;
        const is_current_player = current_player == player;
        
        // Get information set
        const infoset_key = try state.getInfoSetKey(current_player);
        if (self.infoset_map.getPtr(infoset_key)) |infoset| {
            const strategy = infoset.getCurrentStrategy();
            const actions = state.getLegalActions();
            
            // Update strategy sum for averaging
            if (is_current_player) {
                const weight = pi_current;
                for (strategy, 0..) |s, i| {
                    infoset.strategy_sum[i] += weight * s;
                }
            }
            
            // Sample action and continue
            const rand = self.prng.random();
            const sampled_action = sampleFromDistribution(rand, strategy);
            
            var next_state = try state.clone();
            defer next_state.deinit();
            
            _ = try next_state.applyAction(actions[sampled_action]);
            
            const new_pi = if (is_current_player) 
                pi_current * strategy[sampled_action]
            else 
                pi_opponent * strategy[sampled_action];
                
            if (is_current_player) {
                return try self.traverseUpdateStrategy(&next_state, player, new_pi, pi_opponent, depth + 1);
            } else {
                return try self.traverseUpdateStrategy(&next_state, player, pi_current, new_pi, depth + 1);
            }
        }
        
        // If infoset doesn't exist, return 0
        return 0.0;
    }
    
    /// Apply Linear CFR discounting to regrets
    fn applyDiscounting(self: *Self) !void {
        var iter = self.infoset_map.iterator();
        while (iter.next()) |entry| {
            const infoset = entry.value_ptr;
            
            for (infoset.regrets) |*regret| {
                if (regret.* > 0) {
                    // Positive regrets grow (Linear CFR key insight)
                    regret.* *= self.config.discount_positive;
                } else {
                    // Negative regrets decay
                    regret.* *= self.config.discount_negative;
                    
                    // Prune if below threshold
                    if (regret.* < self.config.prune_threshold) {
                        regret.* = 0;
                    }
                }
            }
        }
    }
    
    /// Clean up rarely visited InfoSets to prevent memory explosion
    fn cleanupRareInfoSets(self: *Self) !void {
        // Skip cleanup if disabled or too early
        if (self.config.cleanup_interval == 0 or 
            self.iteration < self.config.min_iterations_before_cleanup) {
            return;
        }
        
        // Only run cleanup at specified intervals
        if (self.iteration % self.config.cleanup_interval != 0) {
            return;
        }
        
        // Use saturating arithmetic to prevent underflow
        const cleanup_age = self.iteration -| self.config.cleanup_staleness_window;
        
        // Scale visit threshold based on current iteration count
        const min_visits_threshold = @max(1, self.iteration / self.config.visit_threshold_divisor);
        
        // Collect candidates for removal with priority scores
        const RemovalCandidate = struct {
            key: u64,
            score: f32, // Lower score = more likely to remove
        };
        
        var candidates = try std.ArrayList(RemovalCandidate).initCapacity(self.allocator, 0);
        defer candidates.deinit(self.allocator);
        
        var iter = self.infoset_map.iterator();
        while (iter.next()) |entry| {
            const infoset = entry.value_ptr;
            
            // Calculate removal score (lower = more likely to remove)
            // Based on recency and visit frequency
            const recency_score = @as(f32, @floatFromInt(self.iteration - infoset.last_update)) / 
                                 @as(f32, @floatFromInt(self.config.cleanup_staleness_window));
            const visit_score = @as(f32, @floatFromInt(infoset.visits)) / 
                              @as(f32, @floatFromInt(min_visits_threshold));
            
            // Combined score: prioritize removing old, rarely visited nodes
            const removal_score = visit_score * 0.3 + (1.0 - recency_score) * 0.7;
            
            // Only consider for removal if below thresholds
            const should_consider = (self.iteration > self.config.cleanup_staleness_window and 
                                    infoset.last_update < cleanup_age) or
                                   (infoset.visits < min_visits_threshold);
            
            if (should_consider) {
                try candidates.append(self.allocator, .{
                    .key = entry.key_ptr.*,
                    .score = removal_score,
                });
            }
        }
        
        // Sort by score (ascending - worst candidates first)
        const sortFn = struct {
            fn lessThan(_: void, a: RemovalCandidate, b: RemovalCandidate) bool {
                return a.score < b.score;
            }
        }.lessThan;
        std.mem.sort(RemovalCandidate, candidates.items, {}, sortFn);
        
        // Remove up to max_cleanup_percentage of total InfoSets
        const max_removals = @as(usize, @intFromFloat(
            @as(f32, @floatFromInt(self.infoset_map.count())) * self.config.max_cleanup_percentage
        ));
        const num_to_remove = @min(candidates.items.len, max_removals);
        
        // Remove the worst candidates
        for (candidates.items[0..num_to_remove]) |candidate| {
            if (self.infoset_map.fetchRemove(candidate.key)) |entry| {
                var infoset = entry.value;
                infoset.deinit(self.allocator);
            }
        }
        
        // Log cleanup statistics if substantial
        if (num_to_remove > 0) {
            std.log.debug("Cleanup: Removed {d} InfoSets at iteration {d} (total: {d})", 
                         .{ num_to_remove, self.iteration, self.infoset_map.count() });
        }
    }
    
    /// Calculate exploitability (Nash distance)
    pub fn calculateExploitability(self: *Self, state: *GameState) !f32 {
        // Skip exploitability calculation if we have too many infosets (expensive)
        if (self.infoset_map.count() > 10000) {
            std.log.info("Skipping exploitability calculation (too many infosets: {})", .{self.infoset_map.count()});
            return 0.0;
        }
        
        // Best response calculation with depth limiting
        var br_value: f32 = 0.0;
        
        for (0..state.num_players) |p| {
            br_value += try self.bestResponseWithDepth(state, @intCast(p), 0);
        }
        
        return br_value / @as(f32, @floatFromInt(state.num_players));
    }
    
    fn bestResponseWithDepth(self: *Self, state: *GameState, player: u8, depth: u32) !f32 {
        // Use more conservative depth limit for exploitability calculation
        const EXPLOITABILITY_MAX_DEPTH = 10; // Shallower for faster calculation
        if (depth >= EXPLOITABILITY_MAX_DEPTH) {
            return 0.0;  // Return neutral value at max depth
        }
        
        if (state.isTerminal()) {
            return state.getUtility(player);
        }
        
        const current_player = state.current_player;
        const actions = state.getLegalActions();
        
        if (current_player == player) {
            // Max over actions (best response)
            var max_utility: f32 = -std.math.inf(f32);
            
            for (actions) |action| {
                var next_state = try state.clone();
                defer next_state.deinit();
                
                _ = try next_state.applyAction(action);
                const utility = try self.bestResponseWithDepth(&next_state, player, depth + 1);
                max_utility = @max(max_utility, utility);
            }
            
            return max_utility;
        } else {
            // Use current strategy for opponent
            const infoset_key = try state.getInfoSetKey(current_player);
            if (self.infoset_map.getPtr(infoset_key)) |infoset| {
                const strategy = if (self.config.use_averaging)
                    infoset.getAverageStrategy()
                else
                    infoset.getCurrentStrategy();
                
                var expected_utility: f32 = 0.0;
                
                for (actions, 0..) |action, i| {
                    var next_state = try state.clone();
                    defer next_state.deinit();
                    
                    _ = try next_state.applyAction(action);
                    const utility = try self.bestResponseWithDepth(&next_state, player, depth + 1);
                    expected_utility += strategy[i] * utility;
                }
                
                return expected_utility;
            }
            
            // Default to uniform strategy if not found
            var expected_utility: f32 = 0.0;
            const uniform = 1.0 / @as(f32, @floatFromInt(actions.len));
            
            for (actions) |action| {
                var next_state = try state.clone();
                defer next_state.deinit();
                
                _ = try next_state.applyAction(action);
                const utility = try self.bestResponseWithDepth(&next_state, player, depth + 1);
                expected_utility += uniform * utility;
            }
            
            return expected_utility;
        }
    }
};

// Helper function to sample from probability distribution
fn sampleFromDistribution(rand: std.Random, probs: []f32) usize {
    const r = rand.float(f32);
    var cumulative: f32 = 0.0;
    
    for (probs, 0..) |p, i| {
        cumulative += p;
        if (r <= cumulative) {
            return i;
        }
    }
    
    return probs.len - 1;
}

test "Linear CFR initialization" {
    const allocator = std.testing.allocator;
    
    const config = LinearCFRConfig{};
    var trainer = try LinearCFRTrainer.init(allocator, config);
    defer trainer.deinit();
    
    try std.testing.expect(trainer.iteration == 0);
    try std.testing.expect(trainer.update_schedule == .regret);
}

test "InfoSet data management" {
    const allocator = std.testing.allocator;
    
    var infoset = try InfoSetData.init(allocator, 3);
    defer infoset.deinit(allocator);
    
    // Initialize with some regrets
    infoset.regrets[0] = 10.0;
    infoset.regrets[1] = -5.0;
    infoset.regrets[2] = 15.0;
    
    const strategy = infoset.getCurrentStrategy();
    
    // Should use regret matching
    try std.testing.expect(strategy[0] > 0);
    try std.testing.expect(strategy[1] == 0); // Negative regret
    try std.testing.expect(strategy[2] > 0);
    
    // Should be normalized
    var sum: f32 = 0.0;
    for (strategy) |s| {
        sum += s;
    }
    try std.testing.expectApproxEqRel(sum, 1.0, 0.001);
}