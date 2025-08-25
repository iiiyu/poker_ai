//! Betting Round Management
//!
//! Manages betting rounds, tracking raises, calls, and betting completion
//! Handles complex scenarios like all-ins and betting caps
//!
//! Features:
//! - Betting round state tracking
//! - Raise counting and limits
//! - Action sequence validation
//! - Betting completion detection
//! - Turn order management

const std = @import("std");
const player = @import("player.zig");
const game_engine = @import("game_engine.zig");

pub const ChipAmount = u32;
pub const PlayerId = u8;
pub const Player = player.Player;
pub const MAX_PLAYERS = game_engine.MAX_PLAYERS;

/// Betting round state
pub const BettingRound = enum(u8) {
    pre_flop = 0,
    flop = 1,
    turn = 2,
    river = 3,
    complete = 4,

    pub fn toString(self: BettingRound) []const u8 {
        return switch (self) {
            .pre_flop => "pre_flop",
            .flop => "flop",
            .turn => "turn",
            .river => "river",
            .complete => "complete",
        };
    }
};

/// Betting action summary for round tracking
pub const ActionSummary = struct {
    player_id: PlayerId,
    action_type: u8, // ActionType enum value
    amount: ChipAmount,
    timestamp: u64,

    pub fn init(player_id: PlayerId, action_type: u8, amount: ChipAmount) ActionSummary {
        return ActionSummary{
            .player_id = player_id,
            .action_type = action_type,
            .amount = amount,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }
};

/// Comprehensive betting round manager
pub const BettingManager = struct {
    // Current betting state
    current_bet: ChipAmount,
    last_raiser: ?PlayerId,
    last_aggressor: ?PlayerId,

    // Round tracking
    current_round: BettingRound,
    num_raises_this_round: u8,
    num_players_acted: u8,
    num_players_to_act: u8,

    // Player tracking
    players_who_acted: [MAX_PLAYERS]bool,
    player_final_actions: [MAX_PLAYERS]?u8, // Last action type for each player

    // Action history for this round
    action_sequence: std.ArrayList(ActionSummary),

    // Betting constraints
    min_raise_amount: ChipAmount,
    max_raises_allowed: u8,

    // Turn management
    current_turn: PlayerId,
    first_to_act: PlayerId,
    last_to_act: PlayerId,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .current_bet = 0,
            .last_raiser = null,
            .last_aggressor = null,
            .current_round = .pre_flop,
            .num_raises_this_round = 0,
            .num_players_acted = 0,
            .num_players_to_act = 0,
            .players_who_acted = [_]bool{false} ** MAX_PLAYERS,
            .player_final_actions = [_]?u8{null} ** MAX_PLAYERS,
            .action_sequence = undefined, // Will be set with allocator
            .min_raise_amount = 0,
            .max_raises_allowed = 3,
            .current_turn = 0,
            .first_to_act = 0,
            .last_to_act = 0,
            .allocator = undefined,
        };
    }

    pub fn initWithAllocator(allocator: std.mem.Allocator) Self {
        var manager = Self.init();
        manager.allocator = allocator;
        manager.action_sequence = std.ArrayList(ActionSummary).init(allocator);
        return manager;
    }

    pub fn deinit(self: *Self) void {
        if (@hasField(@TypeOf(self.action_sequence), "allocator")) {
            self.action_sequence.deinit();
        }
    }

    pub fn reset(self: *Self) void {
        self.current_bet = 0;
        self.last_raiser = null;
        self.last_aggressor = null;
        self.current_round = .pre_flop;
        self.num_raises_this_round = 0;
        self.num_players_acted = 0;
        self.num_players_to_act = 0;
        self.players_who_acted = [_]bool{false} ** MAX_PLAYERS;
        self.player_final_actions = [_]?u8{null} ** MAX_PLAYERS;
        if (@hasField(@TypeOf(self.action_sequence), "allocator")) {
            self.action_sequence.clearRetainingCapacity();
        }
        self.min_raise_amount = 0;
        self.current_turn = 0;
        self.first_to_act = 0;
        self.last_to_act = 0;
    }

    /// Start a new betting round
    pub fn startRound(self: *Self, players: []Player, first_to_act: PlayerId, forced_bet: ChipAmount) !void {
        self.current_bet = forced_bet;
        self.last_raiser = null;
        self.last_aggressor = null;
        self.num_raises_this_round = 0;
        self.num_players_acted = 0;
        self.players_who_acted = [_]bool{false} ** MAX_PLAYERS;
        self.player_final_actions = [_]?u8{null} ** MAX_PLAYERS;

        // Count players who can act
        self.num_players_to_act = 0;
        for (players) |p| {
            if (p.canAct()) {
                self.num_players_to_act += 1;
            }
        }

        self.current_turn = first_to_act;
        self.first_to_act = first_to_act;
        self.last_to_act = self.findLastToAct(players, first_to_act);

        if (@hasField(@TypeOf(self.action_sequence), "allocator")) {
            self.action_sequence.clearRetainingCapacity();
        }
    }

    /// Record a player action
    pub fn recordAction(self: *Self, action: struct { action_type: u8, player_id: PlayerId, amount: ChipAmount }) void {
        // Bounds check
        if (action.player_id >= MAX_PLAYERS) return;

        // Mark player as having acted
        if (!self.players_who_acted[action.player_id]) {
            self.players_who_acted[action.player_id] = true;
            self.num_players_acted += 1;
        }

        // Record final action for this player
        self.player_final_actions[action.player_id] = action.action_type;

        // Record action in sequence
        if (@hasField(@TypeOf(self.action_sequence), "allocator")) {
            const summary = ActionSummary.init(action.player_id, action.action_type, action.amount);
            self.action_sequence.append(summary) catch {};
        }
    }

    /// Register a raise action
    pub fn registerRaise(self: *Self, player_id: PlayerId, total_bet: ChipAmount) void {
        const previous_bet = self.current_bet;
        self.current_bet = total_bet;
        self.last_raiser = player_id;
        self.last_aggressor = player_id;
        self.num_raises_this_round += 1;

        // Update minimum raise amount (typically the size of the last raise)
        const raise_size = total_bet - previous_bet;
        self.min_raise_amount = raise_size;

        // Reset action tracking since raise reopens action
        for (&self.players_who_acted, 0..) |*acted, i| {
            if (i != player_id) {
                acted.* = false;
            }
        }
        self.num_players_acted = 1; // Only the raiser has acted
    }

    /// Check if betting round is complete
    pub fn isRoundComplete(self: Self, players: []const Player) bool {
        // If only one player can act, round is complete
        var players_who_can_act: u8 = 0;
        for (players) |p| {
            if (p.canAct()) players_who_can_act += 1;
        }

        if (players_who_can_act <= 1) return true;

        // Check if all players have acted and bets are equal
        var all_acted = true;
        var all_bets_equal = true;

        for (players, 0..) |p, i| {
            if (p.canAct()) {
                if (!self.players_who_acted[i]) {
                    all_acted = false;
                }
                if (p.current_bet != self.current_bet and !p.is_all_in) {
                    all_bets_equal = false;
                }
            }
        }

        return all_acted and all_bets_equal;
    }

    /// Get amount needed to call for a player
    pub fn getCallAmount(self: Self, player_id: PlayerId) ChipAmount {
        _ = player_id;
        return self.current_bet;
    }

    /// Check if raises are capped for this round
    pub fn areRaisesCapped(self: Self) bool {
        return self.num_raises_this_round >= self.max_raises_allowed;
    }

    /// Get minimum raise amount for current situation
    pub fn getMinRaiseAmount(self: Self) ChipAmount {
        return @max(self.min_raise_amount, self.current_bet);
    }

    /// Get next player to act
    pub fn getNextToAct(self: Self, players: []const Player) ?PlayerId {
        var next = (self.current_turn + 1) % @as(u8, @intCast(players.len));
        var count: u8 = 0;

        while (count < players.len) {
            if (players[next].canAct() and !self.players_who_acted[next]) {
                return next;
            }
            next = (next + 1) % @as(u8, @intCast(players.len));
            count += 1;
        }

        return null;
    }

    /// Check if action is reopened (can act again due to raise)
    pub fn isActionReopened(self: Self, player_id: PlayerId, players: []const Player) bool {
        // Action is reopened if there was a raise after this player's last action
        if (self.last_raiser == null) return false;
        if (self.players_who_acted[player_id] and self.last_raiser != player_id) {
            // Check if player can still act (not all-in, not folded)
            return players[player_id].canAct();
        }
        return false;
    }

    /// Get betting round statistics
    pub fn getRoundStats(self: Self) BettingRoundStats {
        return BettingRoundStats{
            .total_actions = if (@hasField(@TypeOf(self.action_sequence), "allocator"))
                @intCast(self.action_sequence.items.len)
            else
                0,
            .num_raises = self.num_raises_this_round,
            .current_bet = self.current_bet,
            .players_acted = self.num_players_acted,
            .players_to_act = self.num_players_to_act,
            .last_aggressor = self.last_aggressor,
            .raises_capped = self.areRaisesCapped(),
        };
    }

    /// Check if player needs to act
    pub fn playerNeedsToAct(self: Self, player_id: PlayerId, players: []const Player) bool {
        const p = &players[player_id];

        // Can't act if not active or all-in
        if (!p.canAct()) return false;

        // Must act if haven't acted yet
        if (!self.players_who_acted[player_id]) return true;

        // Must act if there was a raise after their last action
        if (self.isActionReopened(player_id, players)) return true;

        // Must act if their bet is less than current bet and they're not all-in
        if (p.current_bet < self.current_bet and !p.is_all_in) return true;

        return false;
    }

    /// Advance to next betting round
    pub fn advanceRound(self: *Self) void {
        self.current_round = switch (self.current_round) {
            .pre_flop => .flop,
            .flop => .turn,
            .turn => .river,
            .river => .complete,
            .complete => .complete,
        };

        // Reset for new round
        self.current_bet = 0;
        self.last_raiser = null;
        self.num_raises_this_round = 0;
        self.num_players_acted = 0;
        self.players_who_acted = [_]bool{false} ** 8;
        self.player_final_actions = [_]?u8{null} ** 8;
        self.min_raise_amount = 0;
    }

    /// Get action history for this round
    pub fn getActionHistory(self: Self) []const ActionSummary {
        if (@hasField(@TypeOf(self.action_sequence), "allocator")) {
            return self.action_sequence.items;
        }
        return &[_]ActionSummary{};
    }

    /// Validate betting state consistency
    pub fn validateState(self: Self, players: []const Player) !void {
        // Check that acted player count is consistent
        var counted_acted: u8 = 0;
        for (self.players_who_acted) |acted| {
            if (acted) counted_acted += 1;
        }

        if (counted_acted != self.num_players_acted) {
            return error.InconsistentActionCount;
        }

        // Check that current bet is not higher than any player's current bet
        for (players) |p| {
            if (p.is_active and !p.is_all_in and p.current_bet > self.current_bet) {
                return error.PlayerBetExceedsCurrent;
            }
        }

        // Check that last raiser actually has the current bet
        if (self.last_raiser) |raiser_id| {
            if (players[raiser_id].current_bet != self.current_bet) {
                return error.LastRaiserBetMismatch;
            }
        }
    }

    // Private helper methods

    fn findLastToAct(self: Self, players: []const Player, first_to_act: PlayerId) PlayerId {
        _ = self;
        var last = first_to_act;

        for (players, 0..) |p, i| {
            if (p.canAct()) {
                last = @intCast(i);
            }
        }

        return last;
    }
};

/// Statistics for a betting round
pub const BettingRoundStats = struct {
    total_actions: u16,
    num_raises: u8,
    current_bet: ChipAmount,
    players_acted: u8,
    players_to_act: u8,
    last_aggressor: ?PlayerId,
    raises_capped: bool,
};

/// Betting pattern analyzer
pub const BettingPatternAnalyzer = struct {
    action_history: std.ArrayList(ActionSummary),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BettingPatternAnalyzer {
        return BettingPatternAnalyzer{
            .action_history = std.ArrayList(ActionSummary).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BettingPatternAnalyzer) void {
        self.action_history.deinit();
    }

    pub fn addAction(self: *BettingPatternAnalyzer, action: ActionSummary) !void {
        try self.action_history.append(action);
    }

    /// Get aggression factor for a player
    pub fn getAggressionFactor(self: BettingPatternAnalyzer, player_id: PlayerId) f32 {
        var aggressive_actions: f32 = 0;
        var passive_actions: f32 = 0;

        for (self.action_history.items) |action| {
            if (action.player_id == player_id) {
                switch (action.action_type) {
                    2, 4 => aggressive_actions += 1, // raise, all_in
                    1 => passive_actions += 1, // call
                    else => {},
                }
            }
        }

        if (passive_actions == 0) return if (aggressive_actions > 0) std.math.inf(f32) else 0;
        return aggressive_actions / passive_actions;
    }

    /// Get VPIP (Voluntarily Put money In Pot) percentage
    pub fn getVPIP(self: BettingPatternAnalyzer, player_id: PlayerId, total_hands: u32) f32 {
        var voluntary_hands: u32 = 0;

        for (self.action_history.items) |action| {
            if (action.player_id == player_id and action.action_type != 0) { // Not fold
                voluntary_hands += 1;
                break; // Only count once per hand
            }
        }

        if (total_hands == 0) return 0;
        return @as(f32, @floatFromInt(voluntary_hands)) / @as(f32, @floatFromInt(total_hands)) * 100.0;
    }
};

// Unit tests
test "betting manager initialization" {
    const testing = std.testing;

    var manager = BettingManager.initWithAllocator(testing.allocator);
    defer manager.deinit();

    try testing.expectEqual(@as(ChipAmount, 0), manager.current_bet);
    try testing.expectEqual(@as(u8, 0), manager.num_raises_this_round);
}

test "raise registration" {
    const testing = std.testing;

    var manager = BettingManager.initWithAllocator(testing.allocator);
    defer manager.deinit();

    manager.registerRaise(0, 100);

    try testing.expectEqual(@as(ChipAmount, 100), manager.current_bet);
    try testing.expectEqual(@as(?PlayerId, 0), manager.last_raiser);
    try testing.expectEqual(@as(u8, 1), manager.num_raises_this_round);
}

test "round completion detection" {
    const testing = std.testing;

    var manager = BettingManager.initWithAllocator(testing.allocator);
    defer manager.deinit();

    var players = [_]Player{
        Player.init(0, 1000),
        Player.init(1, 1000),
    };

    // Start round
    try manager.startRound(&players, 0, 0);

    // Both players act
    manager.recordAction(.{ .action_type = 1, .player_id = 0, .amount = 0 }); // call
    manager.recordAction(.{ .action_type = 3, .player_id = 1, .amount = 0 }); // check

    try testing.expect(manager.isRoundComplete(&players));
}

test "betting pattern analysis" {
    const testing = std.testing;

    var analyzer = BettingPatternAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.addAction(ActionSummary.init(0, 2, 100)); // raise
    try analyzer.addAction(ActionSummary.init(0, 1, 50)); // call

    const aggression = analyzer.getAggressionFactor(0);
    try testing.expectEqual(@as(f32, 1.0), aggression); // 1 raise / 1 call = 1.0
}
