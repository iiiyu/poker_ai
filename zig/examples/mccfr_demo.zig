// MCCFR Demo - Demonstration of Monte Carlo CFR implementation
// Shows convergence on a simplified poker variant

const std = @import("std");

// Simple game for demonstration (simplified Kuhn-like poker)
const SimplePoker = struct {
    const Card = enum(u8) { low = 0, mid = 1, high = 2 };
    const Action = enum(u8) { fold = 0, check = 1, bet = 2, call = 3 };

    cards: [2]Card,
    history: std.ArrayList(Action),
    pot: [2]i32,
    current_player: u8,

    pub fn init(allocator: std.mem.Allocator, card1: Card, card2: Card) !SimplePoker {
        return .{
            .cards = .{ card1, card2 },
            .history = std.ArrayList(Action).init(allocator),
            .pot = .{ 1, 1 },
            .current_player = 0,
        };
    }

    pub fn deinit(self: *SimplePoker) void {
        self.history.deinit();
    }

    pub fn isTerminal(self: *SimplePoker) bool {
        const h = self.history.items;
        if (h.len < 2) return false;

        // Check-Check ends game
        if (h[h.len - 2] == .check and h[h.len - 1] == .check) return true;
        // Bet-Fold ends game
        if (h[h.len - 2] == .bet and h[h.len - 1] == .fold) return true;
        // Bet-Call ends game
        if (h[h.len - 2] == .bet and h[h.len - 1] == .call) return true;

        return false;
    }

    pub fn getPayoff(self: *SimplePoker, player: u8) f32 {
        if (!self.isTerminal()) return 0.0;

        const h = self.history.items;
        const last_action = h[h.len - 1];

        if (last_action == .fold) {
            // Folder loses
            const winner = if (h.len % 2 == 0) @as(u8, 0) else @as(u8, 1);
            return if (player == winner) 1.0 else -1.0;
        }

        // Showdown
        const p1_card = @intFromEnum(self.cards[0]);
        const p2_card = @intFromEnum(self.cards[1]);

        if (p1_card > p2_card) {
            return if (player == 0) @floatFromInt(self.pot[1]) else -@as(f32, @floatFromInt(self.pot[0]));
        } else {
            return if (player == 1) @floatFromInt(self.pot[0]) else -@as(f32, @floatFromInt(self.pot[1]));
        }
    }

    pub fn getLegalActions(self: *SimplePoker) []const Action {
        if (self.history.items.len == 0) {
            return &[_]Action{ .check, .bet };
        }

        const last = self.history.items[self.history.items.len - 1];
        if (last == .bet) {
            return &[_]Action{ .fold, .call };
        } else {
            return &[_]Action{ .check, .bet };
        }
    }

    pub fn applyAction(self: *SimplePoker, action: Action) !void {
        try self.history.append(allocator, action);

        if (action == .bet) {
            self.pot[self.current_player] += 1;
        } else if (action == .call) {
            self.pot[self.current_player] += 1;
        }

        self.current_player = 1 - self.current_player;
    }

    pub fn getInfoSetString(self: *SimplePoker, player: u8) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.history.allocator);

        // Add player's card
        const card_char: u8 = switch (self.cards[player]) {
            .low => 'L',
            .mid => 'M',
            .high => 'H',
        };
        try buffer.append(allocator, card_char);

        // Add action history
        for (self.history.items) |action| {
            const action_char: u8 = switch (action) {
                .fold => 'f',
                .check => 'x',
                .bet => 'b',
                .call => 'c',
            };
            try buffer.append(allocator, action_char);
        }

        return buffer.toOwnedSlice();
    }
};

// Simplified CFR trainer
const SimpleCFR = struct {
    regrets: std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    strategy_sum: std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SimpleCFR {
        return .{
            .regrets = std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .strategy_sum = std.HashMap(u64, []f32, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimpleCFR) void {
        var iter = self.regrets.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.regrets.deinit();

        iter = self.strategy_sum.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.strategy_sum.deinit();
    }

    fn hashInfoSet(info_set: []const u8) u64 {
        return std.hash.Wyhash.hash(0, info_set);
    }

    fn getStrategy(self: *SimpleCFR, info_set: []const u8, num_actions: usize) ![]f32 {
        const hash = hashInfoSet(info_set);

        // Get or create regret array
        const regret_entry = try self.regrets.getOrPut(hash);
        if (!regret_entry.found_existing) {
            regret_entry.value_ptr.* = try self.allocator.alloc(f32, num_actions);
            @memset(regret_entry.value_ptr.*, 0.0);
        }

        // Calculate strategy from regrets
        const regrets = regret_entry.value_ptr.*;
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

        // Initialize strategy sum if needed
        const strat_entry = try self.strategy_sum.getOrPut(hash);
        if (!strat_entry.found_existing) {
            strat_entry.value_ptr.* = try self.allocator.alloc(f32, num_actions);
            @memset(strat_entry.value_ptr.*, 0.0);
        }

        return strategy;
    }

    pub fn mccfr(self: *SimpleCFR, game: *SimplePoker, player: u8, pi: [2]f32) !f32 {
        if (game.isTerminal()) {
            return game.getPayoff(player);
        }

        const current_player = game.current_player;
        const info_set = try game.getInfoSetString(current_player);
        defer self.allocator.free(info_set);

        const actions = game.getLegalActions();
        const strategy = try self.getStrategy(info_set, actions.len);
        defer self.allocator.free(strategy);

        // Sample action for current player
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const rng = prng.random();

        var sampled_action: usize = 0;
        if (current_player == player) {
            // For the traversing player, sample from strategy
            const r = rng.float(f32);
            var cumulative: f32 = 0.0;
            for (strategy, 0..) |prob, i| {
                cumulative += prob;
                if (r <= cumulative) {
                    sampled_action = i;
                    break;
                }
            }
        } else {
            // For opponent, use epsilon-greedy exploration
            if (rng.float(f32) < 0.6) {
                sampled_action = rng.uintLessThan(usize, actions.len);
            } else {
                const r = rng.float(f32);
                var cumulative: f32 = 0.0;
                for (strategy, 0..) |prob, i| {
                    cumulative += prob;
                    if (r <= cumulative) {
                        sampled_action = i;
                        break;
                    }
                }
            }
        }

        // Apply sampled action
        try game.applyAction(actions[sampled_action]);

        // Update pi for next recursion
        var new_pi = pi;
        new_pi[current_player] *= strategy[sampled_action];

        // Recurse
        const utility = try self.mccfr(game, player, new_pi);

        // Update regrets if this is the traversing player
        if (current_player == player) {
            const hash = hashInfoSet(info_set);
            const regrets = self.regrets.get(hash).?;
            const strat_sum = self.strategy_sum.get(hash).?;

            // Calculate counterfactual values for all actions
            for (actions, 0..) |_, i| {
                if (i == sampled_action) {
                    // Update regret for sampled action
                    const cf_reach = pi[1 - player];
                    const regret = utility * (1.0 - strategy[i]);
                    regrets[i] += cf_reach * regret;
                } else {
                    // Update regret for unsampled actions
                    const cf_reach = pi[1 - player];
                    const regret = -utility * strategy[i];
                    regrets[i] += cf_reach * regret;
                }

                // Update strategy sum
                strat_sum[i] += pi[player] * strategy[i];
            }
        }

        return utility;
    }

    pub fn train(self: *SimpleCFR, iterations: u32) !void {
        var prng = std.Random.DefaultPrng.init(42);
        const rng = prng.random();

        std.debug.print("Starting MCCFR training for {} iterations...\n", .{iterations});

        var iter: u32 = 0;
        while (iter < iterations) : (iter += 1) {
            // Sample random card permutation
            const cards = [_]SimplePoker.Card{ .low, .mid, .high };
            const idx1 = rng.uintLessThan(usize, 3);
            var idx2 = rng.uintLessThan(usize, 3);
            while (idx2 == idx1) {
                idx2 = rng.uintLessThan(usize, 3);
            }

            // Train both players
            for (0..2) |p| {
                var game = try SimplePoker.init(self.allocator, cards[idx1], cards[idx2]);
                defer game.deinit();

                _ = try self.mccfr(&game, @intCast(p), .{ 1.0, 1.0 });
            }

            if ((iter + 1) % 1000 == 0) {
                std.debug.print("Iteration {}: ", .{iter + 1});
                self.printStrategy();
            }
        }

        std.debug.print("\nTraining complete!\n", .{});
    }

    pub fn getAverageStrategy(self: *SimpleCFR, info_set: []const u8) ?[]f32 {
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

    fn printStrategy(self: *SimpleCFR) void {
        // Print strategy for first player with high card
        if (self.getAverageStrategy("H")) |strat| {
            defer self.allocator.free(strat);
            std.debug.print("P1 High: check={d:.2} bet={d:.2} | ", .{ strat[0], strat[1] });
        }

        // Print strategy for second player facing bet with mid card
        if (self.getAverageStrategy("Mb")) |strat| {
            defer self.allocator.free(strat);
            std.debug.print("P2 Mid vs bet: fold={d:.2} call={d:.2}\n", .{ strat[0], strat[1] });
        }
    }

    pub fn printFinalStrategy(self: *SimpleCFR) void {
        std.debug.print("\n=== Final Strategy ===\n", .{});

        const info_sets = [_][]const u8{
            "L", "M", "H", // P1 initial
            "Lb", "Mb", "Hb", // P2 facing bet
            "Lx", "Mx", "Hx", // P2 after check
        };

        for (info_sets) |info_set| {
            if (self.getAverageStrategy(info_set)) |strat| {
                defer self.allocator.free(strat);

                std.debug.print("{s}: ", .{info_set});
                const actions = if (std.mem.indexOf(u8, info_set, "b") != null)
                    &[_][]const u8{ "fold", "call" }
                else
                    &[_][]const u8{ "check", "bet" };

                for (actions, 0..) |action, i| {
                    if (i < strat.len) {
                        std.debug.print("{s}={d:.2} ", .{ action, strat[i] });
                    }
                }
                std.debug.print("\n", .{});
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== MCCFR Demo - Simple Poker Game ===\n\n", .{});
    std.debug.print("Game Rules:\n", .{});
    std.debug.print("- 3 cards: Low, Mid, High\n", .{});
    std.debug.print("- Each player gets 1 card\n", .{});
    std.debug.print("- Players can check/bet, then fold/call\n", .{});
    std.debug.print("- Pot starts at 2 (ante of 1 each)\n\n", .{});

    var cfr = SimpleCFR.init(allocator);
    defer cfr.deinit();

    // Train for 10000 iterations
    try cfr.train(10000);

    // Print final converged strategy
    cfr.printFinalStrategy();

    std.debug.print("\n=== Analysis ===\n", .{});
    std.debug.print("Expected behavior:\n", .{});
    std.debug.print("- High card should bet frequently (value betting)\n", .{});
    std.debug.print("- Low card should sometimes bet (bluffing)\n", .{});
    std.debug.print("- Mid card should mix strategies\n", .{});
    std.debug.print("\nThe strategies above should approximate Nash equilibrium!\n", .{});
}
