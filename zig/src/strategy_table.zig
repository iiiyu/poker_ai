// Strategy and regret table storage for poker AI
// Efficient storage and retrieval of learned strategies

const std = @import("std");
const game_state = @import("game_state.zig");

// Action probability distribution
pub const ActionProbabilities = struct {
    probabilities: []f64,
    actions: []game_state.ActionType,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, actions: []const game_state.ActionType) !Self {
        const probs = try allocator.alloc(f64, actions.len);
        const owned_actions = try allocator.dupe(game_state.ActionType, actions);

        // Initialize with uniform distribution
        const uniform_prob = 1.0 / @as(f64, @floatFromInt(actions.len));
        for (probs) |*prob| {
            prob.* = uniform_prob;
        }

        return Self{
            .probabilities = probs,
            .actions = owned_actions,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.probabilities);
        self.allocator.free(self.actions);
    }

    pub fn setProbability(self: *Self, action: game_state.ActionType, probability: f64) bool {
        for (self.actions, 0..) |a, i| {
            if (a == action) {
                self.probabilities[i] = probability;
                return true;
            }
        }
        return false;
    }

    pub fn getProbability(self: Self, action: game_state.ActionType) ?f64 {
        for (self.actions, 0..) |a, i| {
            if (a == action) {
                return self.probabilities[i];
            }
        }
        return null;
    }

    pub fn normalize(self: *Self) void {
        var sum: f64 = 0.0;
        for (self.probabilities) |prob| {
            sum += prob;
        }

        if (sum > 0.0) {
            for (self.probabilities) |*prob| {
                prob.* /= sum;
            }
        }
    }

    pub fn sampleAction(self: Self, rng: std.Random) game_state.ActionType {
        const rand_val = rng.float(f64);
        var cumulative: f64 = 0.0;

        for (self.actions, 0..) |action, i| {
            cumulative += self.probabilities[i];
            if (rand_val <= cumulative) {
                return action;
            }
        }

        // Fallback to last action
        return self.actions[self.actions.len - 1];
    }
};

// Strategy profile for a specific information set
pub const StrategyProfile = struct {
    info_set_hash: u64,
    action_probs: ActionProbabilities,
    regret_sum: []f64,
    strategy_sum: []f64,
    reach_count: u32,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        info_set_hash: u64,
        actions: []const game_state.ActionType,
    ) !Self {
        const action_probs = try ActionProbabilities.init(allocator, actions);
        const regret_sum = try allocator.alloc(f64, actions.len);
        const strategy_sum = try allocator.alloc(f64, actions.len);

        // Initialize with zeros
        for (regret_sum) |*regret| {
            regret.* = 0.0;
        }
        for (strategy_sum) |*sum| {
            sum.* = 0.0;
        }

        return Self{
            .info_set_hash = info_set_hash,
            .action_probs = action_probs,
            .regret_sum = regret_sum,
            .strategy_sum = strategy_sum,
            .reach_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.action_probs.deinit();
        self.allocator.free(self.regret_sum);
        self.allocator.free(self.strategy_sum);
    }

    pub fn updateRegret(self: *Self, action: game_state.ActionType, regret: f64) void {
        for (self.action_probs.actions, 0..) |a, i| {
            if (a == action) {
                self.regret_sum[i] += regret;
                break;
            }
        }
    }

    pub fn updateStrategy(self: *Self, strategy: []const f64, weight: f64) void {
        for (strategy, 0..) |prob, i| {
            self.strategy_sum[i] += weight * prob;
        }
        self.reach_count += 1;
    }

    pub fn computeCurrentStrategy(self: *Self) void {
        var normalizing_sum: f64 = 0.0;

        // Use regret matching
        for (self.regret_sum, 0..) |regret, i| {
            self.action_probs.probabilities[i] = if (regret > 0) regret else 0;
            normalizing_sum += self.action_probs.probabilities[i];
        }

        // Normalize or use uniform
        if (normalizing_sum > 0) {
            for (self.action_probs.probabilities) |*prob| {
                prob.* /= normalizing_sum;
            }
        } else {
            const uniform_prob = 1.0 / @as(f64, @floatFromInt(self.action_probs.actions.len));
            for (self.action_probs.probabilities) |*prob| {
                prob.* = uniform_prob;
            }
        }
    }

    pub fn getAverageStrategy(self: Self, allocator: std.mem.Allocator) ![]f64 {
        var avg_strategy = try allocator.alloc(f64, self.action_probs.actions.len);
        var normalizing_sum: f64 = 0.0;

        for (self.strategy_sum) |sum| {
            normalizing_sum += sum;
        }

        if (normalizing_sum > 0) {
            for (self.strategy_sum, 0..) |sum, i| {
                avg_strategy[i] = sum / normalizing_sum;
            }
        } else {
            const uniform_prob = 1.0 / @as(f64, @floatFromInt(self.action_probs.actions.len));
            for (avg_strategy) |*prob| {
                prob.* = uniform_prob;
            }
        }

        return avg_strategy;
    }
};

// Main strategy table for storing all learned strategies
pub const StrategyTable = struct {
    strategies: std.hash_map.HashMap(u64, StrategyProfile, std.hash_map.AutoContext(u64), 80),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .strategies = std.hash_map.HashMap(u64, StrategyProfile, std.hash_map.AutoContext(u64), 80).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.strategies.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.strategies.deinit();
    }

    pub fn getOrCreateStrategy(
        self: *Self,
        info_set_hash: u64,
        actions: []const game_state.ActionType,
    ) !*StrategyProfile {
        if (self.strategies.getPtr(info_set_hash)) |strategy| {
            return strategy;
        }

        const new_strategy = try StrategyProfile.init(self.allocator, info_set_hash, actions);
        try self.strategies.put(info_set_hash, new_strategy);
        return self.strategies.getPtr(info_set_hash).?;
    }

    pub fn getStrategy(self: Self, info_set_hash: u64) ?*const StrategyProfile {
        return self.strategies.getPtr(info_set_hash);
    }

    pub fn updateStrategy(
        self: *Self,
        info_set_hash: u64,
        action: game_state.ActionType,
        regret: f64,
        strategy: []const f64,
        weight: f64,
    ) !void {
        // This would typically be called from CFR algorithm
        if (self.strategies.getPtr(info_set_hash)) |profile| {
            profile.updateRegret(action, regret);
            profile.updateStrategy(strategy, weight);
            profile.computeCurrentStrategy();
        }
    }

    pub fn saveToFile(self: Self, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        const writer = file.writer();

        // Write header
        try writer.writeInt(u32, @intCast(self.strategies.count()), .little);

        // Write each strategy
        var iterator = self.strategies.iterator();
        while (iterator.next()) |entry| {
            const hash = entry.key_ptr.*;
            const profile = entry.value_ptr;

            try writer.writeInt(u64, hash, .little);
            try writer.writeInt(u32, @intCast(profile.action_probs.actions.len), .little);

            // Write actions
            for (profile.action_probs.actions) |action| {
                try writer.writeInt(u8, @intFromEnum(action), .little);
            }

            // Write probabilities
            for (profile.action_probs.probabilities) |prob| {
                try writer.writeInt(u64, @bitCast(prob), .little);
            }

            // Write regret sums
            for (profile.regret_sum) |regret| {
                try writer.writeInt(u64, @bitCast(regret), .little);
            }

            // Write strategy sums
            for (profile.strategy_sum) |sum| {
                try writer.writeInt(u64, @bitCast(sum), .little);
            }

            try writer.writeInt(u32, profile.reach_count, .little);
        }
    }

    pub fn loadFromFile(self: *Self, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const reader = file.reader();

        // Read header
        const num_strategies = try reader.readInt(u32, .little);

        // Read each strategy
        for (0..num_strategies) |_| {
            const hash = try reader.readInt(u64, .little);
            const num_actions = try reader.readInt(u32, .little);

            // Read actions
            const actions = try self.allocator.alloc(game_state.ActionType, num_actions);
            defer self.allocator.free(actions);

            for (actions) |*action| {
                const action_byte = try reader.readInt(u8, .little);
                action.* = @enumFromInt(action_byte);
            }

            // Create strategy profile
            var profile = try StrategyProfile.init(self.allocator, hash, actions);

            // Read probabilities
            for (profile.action_probs.probabilities) |*prob| {
                const prob_bits = try reader.readInt(u64, .little);
                prob.* = @bitCast(prob_bits);
            }

            // Read regret sums
            for (profile.regret_sum) |*regret| {
                const regret_bits = try reader.readInt(u64, .little);
                regret.* = @bitCast(regret_bits);
            }

            // Read strategy sums
            for (profile.strategy_sum) |*sum| {
                const sum_bits = try reader.readInt(u64, .little);
                sum.* = @bitCast(sum_bits);
            }

            profile.reach_count = try reader.readInt(u32, .little);

            try self.strategies.put(hash, profile);
        }
    }

    pub fn getMemoryUsage(self: Self) usize {
        var total_size: usize = 0;

        var iterator = self.strategies.iterator();
        while (iterator.next()) |entry| {
            const profile = entry.value_ptr;
            total_size += profile.action_probs.actions.len * (@sizeOf(f64) + @sizeOf(game_state.ActionType));
            total_size += profile.regret_sum.len * @sizeOf(f64);
            total_size += profile.strategy_sum.len * @sizeOf(f64);
            total_size += @sizeOf(StrategyProfile);
        }

        return total_size;
    }
};

test "action probabilities" {
    const testing = std.testing;

    const actions = [_]game_state.ActionType{ .fold, .call, .raise };
    var action_probs = try ActionProbabilities.init(testing.allocator, &actions);
    defer action_probs.deinit();

    try testing.expectEqual(@as(usize, 3), action_probs.actions.len);

    // Test uniform initialization
    for (action_probs.probabilities) |prob| {
        try testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), prob, 0.001);
    }

    // Test setting probability
    try testing.expect(action_probs.setProbability(.fold, 0.5));
    try testing.expectEqual(@as(f64, 0.5), action_probs.getProbability(.fold).?);
}

test "strategy profile" {
    const testing = std.testing;

    const actions = [_]game_state.ActionType{ .fold, .call };
    var profile = try StrategyProfile.init(testing.allocator, 12345, &actions);
    defer profile.deinit();

    try testing.expectEqual(@as(u64, 12345), profile.info_set_hash);
    try testing.expectEqual(@as(u32, 0), profile.reach_count);

    // Test regret update
    profile.updateRegret(.fold, 5.0);
    try testing.expectEqual(@as(f64, 5.0), profile.regret_sum[0]);

    // Test strategy computation
    profile.computeCurrentStrategy();
    try testing.expect(profile.action_probs.probabilities[0] > 0);
}

test "strategy table" {
    const testing = std.testing;

    var table = StrategyTable.init(testing.allocator);
    defer table.deinit();

    const actions = [_]game_state.ActionType{ .fold, .call, .raise };
    const strategy = try table.getOrCreateStrategy(54321, &actions);

    try testing.expectEqual(@as(u64, 54321), strategy.info_set_hash);
    try testing.expect(table.getStrategy(54321) != null);
    try testing.expect(table.getStrategy(99999) == null);
}
