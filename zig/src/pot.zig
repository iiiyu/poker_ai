//! Pot Management with Side Pot Logic
//!
//! Handles main pot and side pot calculations for all-in scenarios
//! Supports complex multi-player all-in situations
//!
//! Features:
//! - Main pot management
//! - Multiple side pots for all-ins
//! - Automatic pot splitting
//! - Winner calculation and distribution
//! - Rake calculations (if needed)

const std = @import("std");
const config = @import("config.zig");
const player = @import("player.zig");
const game_engine = @import("game_engine.zig");

pub const ChipAmount = u32;
pub const PlayerId = u8;
pub const Player = player.Player;
pub const MAX_PLAYERS = game_engine.MAX_PLAYERS;

/// Individual pot (main or side pot)
pub const Pot = struct {
    amount: ChipAmount,
    eligible_players: std.ArrayList(PlayerId),
    max_contribution_per_player: ChipAmount,
    is_side_pot: bool,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_contribution: ChipAmount, is_side: bool) Self {
        return Self{
            .amount = 0,
            .eligible_players = std.ArrayList(PlayerId){},
            .max_contribution_per_player = max_contribution,
            .is_side_pot = is_side,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.eligible_players.deinit(self.allocator);
    }

    pub fn addPlayer(self: *Self, player_id: PlayerId) !void {
        // Check if player already eligible
        for (self.eligible_players.items) |existing_id| {
            if (existing_id == player_id) return;
        }
        try self.eligible_players.append(self.allocator, player_id);
    }

    pub fn isPlayerEligible(self: Self, player_id: PlayerId) bool {
        for (self.eligible_players.items) |eligible_id| {
            if (eligible_id == player_id) return true;
        }
        return false;
    }

    pub fn getEligiblePlayerCount(self: Self) u8 {
        return @intCast(self.eligible_players.items.len);
    }
};

/// Complete pot management system
pub const PotManager = struct {
    main_pot: Pot,
    side_pots: std.ArrayList(Pot),
    total_contributions: [MAX_PLAYERS]ChipAmount, // Track per player contributions
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .main_pot = Pot.init(allocator, std.math.maxInt(ChipAmount), false),
            .side_pots = std.ArrayList(Pot){},
            .total_contributions = [_]ChipAmount{0} ** MAX_PLAYERS,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.main_pot.deinit();
        for (self.side_pots.items) |*side_pot| {
            side_pot.deinit();
        }
        self.side_pots.deinit(self.allocator);
    }

    pub fn reset(self: *Self) void {
        self.main_pot.amount = 0;
        self.main_pot.eligible_players.clearRetainingCapacity();

        for (self.side_pots.items) |*side_pot| {
            side_pot.deinit();
        }
        self.side_pots.clearRetainingCapacity();

        self.total_contributions = [_]ChipAmount{0} ** MAX_PLAYERS;
    }

    /// Add chips to pot from a player
    pub fn addToPot(self: *Self, amount: ChipAmount, player_id: PlayerId) !void {
        if (amount == 0) return;

        // Bounds check
        if (player_id >= MAX_PLAYERS) {
            return error.InvalidPlayerId;
        }

        self.total_contributions[player_id] += amount;

        // First, try to add to main pot
        var remaining = amount;

        // Calculate how much can go to main pot
        const main_pot_capacity = self.main_pot.max_contribution_per_player -
            @min(self.main_pot.max_contribution_per_player, self.getPlayerContributionToPot(player_id, &self.main_pot));

        const to_main_pot = @min(remaining, main_pot_capacity);
        if (to_main_pot > 0) {
            self.main_pot.amount += to_main_pot;
            try self.main_pot.addPlayer(player_id);
            remaining -= to_main_pot;
        }

        // Handle remaining amount in side pots
        while (remaining > 0) {
            var added_to_existing = false;

            // Try to add to existing side pots
            for (self.side_pots.items) |*side_pot| {
                const side_pot_capacity = side_pot.max_contribution_per_player -
                    @min(side_pot.max_contribution_per_player, self.getPlayerContributionToPot(player_id, side_pot));

                if (side_pot_capacity > 0) {
                    const to_side_pot = @min(remaining, side_pot_capacity);
                    side_pot.amount += to_side_pot;
                    try side_pot.addPlayer(player_id);
                    remaining -= to_side_pot;
                    added_to_existing = true;
                    break;
                }
            }

            // Create new side pot if needed
            if (!added_to_existing) {
                var new_side_pot = Pot.init(self.allocator, remaining, true);
                new_side_pot.amount = remaining;
                try new_side_pot.addPlayer(player_id);
                try self.side_pots.append(self.allocator, new_side_pot);
                remaining = 0;
            }
        }
    }

    /// Get total pot size (main + all side pots)
    pub fn getTotalPot(self: Self) ChipAmount {
        var total = self.main_pot.amount;
        for (self.side_pots.items) |side_pot| {
            total += side_pot.amount;
        }
        return total;
    }

    /// Calculate payouts for all players based on hand strength
    /// Returns array of payouts indexed by player ID
    pub fn calculatePayouts(self: Self, players: []const Player) ![8]i32 {
        var payouts = [_]i32{0} ** 8;

        // For now, implement simple winner-takes-all
        // In a complete implementation, this would use hand evaluator

        // Find active players eligible for main pot
        var eligible_for_main: std.ArrayList(PlayerId) = try std.ArrayList(PlayerId).initCapacity(self.allocator, 0);
        defer eligible_for_main.deinit(self.allocator);

        for (players, 0..) |p, i| {
            if (p.is_active and self.main_pot.isPlayerEligible(@intCast(i))) {
                try eligible_for_main.append(self.allocator, @intCast(i));
            }
        }

        // Distribute main pot (equal split for now)
        if (eligible_for_main.items.len > 0) {
            const main_pot_share = self.main_pot.amount / @as(ChipAmount, @intCast(eligible_for_main.items.len));
            const main_pot_remainder = self.main_pot.amount % @as(ChipAmount, @intCast(eligible_for_main.items.len));

            for (eligible_for_main.items, 0..) |player_id, i| {
                payouts[player_id] += @intCast(main_pot_share);
                if (i < main_pot_remainder) {
                    payouts[player_id] += 1; // Distribute remainder
                }
            }
        }

        // Distribute side pots
        for (self.side_pots.items) |side_pot| {
            var eligible_for_side: std.ArrayList(PlayerId) = try std.ArrayList(PlayerId).initCapacity(self.allocator, 0);
            defer eligible_for_side.deinit(self.allocator);

            for (players, 0..) |p, i| {
                if (p.is_active and side_pot.isPlayerEligible(@intCast(i))) {
                    try eligible_for_side.append(self.allocator, @intCast(i));
                }
            }

            if (eligible_for_side.items.len > 0) {
                const side_pot_share = side_pot.amount / @as(ChipAmount, @intCast(eligible_for_side.items.len));
                const side_pot_remainder = side_pot.amount % @as(ChipAmount, @intCast(eligible_for_side.items.len));

                for (eligible_for_side.items, 0..) |player_id, i| {
                    payouts[player_id] += @intCast(side_pot_share);
                    if (i < side_pot_remainder) {
                        payouts[player_id] += 1;
                    }
                }
            }
        }

        return payouts;
    }

    /// Calculate side pots based on all-in amounts
    pub fn recalculateSidePots(self: *Self, players: []const Player) !void {
        // Clear existing side pots
        for (self.side_pots.items) |*side_pot| {
            side_pot.deinit();
        }
        self.side_pots.clearRetainingCapacity();

        // Collect all-in amounts
        var all_in_amounts = try std.ArrayList(ChipAmount).initCapacity(self.allocator, 0);
        defer all_in_amounts.deinit();

        for (players) |p| {
            if (p.is_all_in and p.is_active) {
                try all_in_amounts.append(self.allocator, p.total_bet);
            }
        }

        // Sort all-in amounts
        std.sort.block(ChipAmount, all_in_amounts.items, {}, comptime std.sort.asc(ChipAmount));

        // Create side pots for each all-in level
        var prev_amount: ChipAmount = 0;
        for (all_in_amounts.items) |all_in_amount| {
            if (all_in_amount > prev_amount) {
                const side_pot_max = all_in_amount;
                var side_pot = Pot.init(self.allocator, side_pot_max, true);

                // Add eligible players to this side pot
                for (players, 0..) |p, i| {
                    if (p.is_active and p.total_bet >= all_in_amount) {
                        try side_pot.addPlayer(@intCast(i));
                    }
                }

                try self.side_pots.append(self.allocator, side_pot);
                prev_amount = all_in_amount;
            }
        }
    }

    /// Get pot breakdown for display
    pub fn getPotBreakdown(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var breakdown = try std.ArrayList(u8).initCapacity(allocator, 0);
        defer breakdown.deinit();

        try breakdown.writer().print("Main Pot: {} ({} players)\n", .{ self.main_pot.amount, self.main_pot.getEligiblePlayerCount() });

        for (self.side_pots.items, 0..) |side_pot, i| {
            try breakdown.writer().print("Side Pot {}: {} ({} players)\n", .{ i + 1, side_pot.amount, side_pot.getEligiblePlayerCount() });
        }

        try breakdown.writer().print("Total: {}\n", .{self.getTotalPot()});

        return breakdown.toOwnedSlice(self.allocator);
    }

    /// Get contribution of a player to a specific pot
    fn getPlayerContributionToPot(self: Self, player_id: PlayerId, pot_ref: *const Pot) ChipAmount {
        _ = self;
        _ = player_id;
        _ = pot_ref;
        // For now, return 0. In full implementation, track per-pot contributions
        return 0;
    }

    /// Validate pot integrity
    pub fn validatePots(self: Self, players: []const Player) !void {
        var total_contributions: ChipAmount = 0;
        for (players) |p| {
            total_contributions += p.total_bet;
        }

        const total_in_pots = self.getTotalPot();
        if (total_contributions != total_in_pots) {
            return error.PotMismatch;
        }
    }

    /// Calculate rake (house commission)
    pub fn calculateRake(self: Self, rake_percentage: f32, max_rake: ChipAmount) ChipAmount {
        const total_pot = self.getTotalPot();
        const calculated_rake = @as(ChipAmount, @intFromFloat(@as(f32, @floatFromInt(total_pot)) * rake_percentage / 100.0));
        return @min(calculated_rake, max_rake);
    }

    /// Get pot odds for a player (pot size / call amount)
    pub fn getPotOdds(self: Self, call_amount: ChipAmount) f32 {
        if (call_amount == 0) return std.math.inf(f32);
        const total_pot = self.getTotalPot();
        return @as(f32, @floatFromInt(total_pot)) / @as(f32, @floatFromInt(call_amount));
    }

    /// Get implied odds based on potential future betting
    pub fn getImpliedOdds(self: Self, call_amount: ChipAmount, estimated_future_bets: ChipAmount) f32 {
        if (call_amount == 0) return std.math.inf(f32);
        const total_pot = self.getTotalPot() + estimated_future_bets;
        return @as(f32, @floatFromInt(total_pot)) / @as(f32, @floatFromInt(call_amount));
    }
};

/// All-in scenario handler
pub const AllInScenario = struct {
    all_in_players: std.ArrayList(PlayerId),
    all_in_amounts: std.ArrayList(ChipAmount),
    side_pot_structure: std.ArrayList(SidePotInfo),
    allocator: std.mem.Allocator,

    const SidePotInfo = struct {
        max_contribution: ChipAmount,
        eligible_players: std.ArrayList(PlayerId),
        amount: ChipAmount,
    };

    pub fn init(allocator: std.mem.Allocator) AllInScenario {
        return AllInScenario{
            .all_in_players = std.ArrayList(PlayerId).init(allocator),
            .all_in_amounts = std.ArrayList(ChipAmount).init(allocator),
            .side_pot_structure = std.ArrayList(SidePotInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AllInScenario) void {
        self.all_in_players.deinit();
        self.all_in_amounts.deinit();
        for (self.side_pot_structure.items) |*info| {
            info.eligible_players.deinit();
        }
        self.side_pot_structure.deinit();
    }

    pub fn addAllIn(self: *AllInScenario, player_id: PlayerId, amount: ChipAmount) !void {
        try self.all_in_players.append(self.allocator, player_id);
        try self.all_in_amounts.append(self.allocator, amount);
    }

    pub fn calculateSidePots(self: *AllInScenario, players: []const Player) !void {
        // Clear existing structure
        for (self.side_pot_structure.items) |*info| {
            info.eligible_players.deinit();
        }
        self.side_pot_structure.clearRetainingCapacity();

        // Create sorted list of unique all-in amounts
        var unique_amounts = try std.ArrayList(ChipAmount).initCapacity(self.allocator, 0);
        defer unique_amounts.deinit();

        for (self.all_in_amounts.items) |amount| {
            var found = false;
            for (unique_amounts.items) |existing| {
                if (existing == amount) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try unique_amounts.append(self.allocator, amount);
            }
        }

        std.sort.block(ChipAmount, unique_amounts.items, {}, comptime std.sort.asc(ChipAmount));

        // Create side pot for each level
        for (unique_amounts.items) |amount| {
            var info = SidePotInfo{
                .max_contribution = amount,
                .eligible_players = std.ArrayList(PlayerId).init(self.allocator),
                .amount = 0,
            };

            // Add eligible players
            for (players, 0..) |p, i| {
                if (p.is_active and p.total_bet >= amount) {
                    try info.eligible_players.append(self.allocator, @intCast(i));
                }
            }

            try self.side_pot_structure.append(self.allocator, info);
        }
    }
};

// Unit tests
test "pot manager initialization" {
    const testing = std.testing;

    var pot_manager = PotManager.init(testing.allocator);
    defer pot_manager.deinit();

    try testing.expectEqual(@as(ChipAmount, 0), pot_manager.getTotalPot());
}

test "simple pot addition" {
    const testing = std.testing;

    var pot_manager = PotManager.init(testing.allocator);
    defer pot_manager.deinit();

    try pot_manager.addToPot(100, 0);
    try pot_manager.addToPot(100, 1);

    try testing.expectEqual(@as(ChipAmount, 200), pot_manager.getTotalPot());
    try testing.expect(pot_manager.main_pot.isPlayerEligible(0));
    try testing.expect(pot_manager.main_pot.isPlayerEligible(1));
}

test "pot odds calculation" {
    const testing = std.testing;

    var pot_manager = PotManager.init(testing.allocator);
    defer pot_manager.deinit();

    try pot_manager.addToPot(200, 0);

    const odds = pot_manager.getPotOdds(50);
    try testing.expectEqual(@as(f32, 4.0), odds); // 200/50 = 4:1
}

test "rake calculation" {
    const testing = std.testing;

    var pot_manager = PotManager.init(testing.allocator);
    defer pot_manager.deinit();

    try pot_manager.addToPot(1000, 0);

    const rake = pot_manager.calculateRake(5.0, 50); // 5% rake, max 50
    try testing.expectEqual(@as(ChipAmount, 50), rake); // 5% of 1000 = 50, capped at max
}
