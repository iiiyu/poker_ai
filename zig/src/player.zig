//! Player State Management
//!
//! Advanced player state tracking for Texas Hold'em poker
//! Matches Python TexasHoldemPokerPlayer functionality
//!
//! Features:
//! - Stack and betting management
//! - Hole card handling
//! - Active/fold state tracking
//! - All-in detection
//! - Position tracking (dealer, blinds)

const std = @import("std");

pub const Card = u8; // 0-51 representation
pub const ChipAmount = u32;
pub const PlayerId = u8;

/// Player state for Texas Hold'em
pub const Player = struct {
    // Identity
    id: PlayerId,

    // Chip management
    stack: ChipAmount,
    initial_stack: ChipAmount,
    current_bet: ChipAmount, // Bet in current round
    total_bet: ChipAmount, // Total bet in current hand

    // Cards
    hole_cards: [2]Card,
    has_cards: bool,

    // State flags
    is_active: bool, // Still in hand (not folded)
    is_all_in: bool, // Has bet entire stack
    is_sitting_out: bool, // Not participating in hand

    // Position flags (updated each hand)
    is_dealer: bool,
    is_small_blind: bool,
    is_big_blind: bool,
    is_turn: bool, // Currently acting

    // Betting round tracking
    has_acted_this_round: bool,
    last_action_aggressive: bool, // Did last action raise/bet

    const Self = @This();

    /// Initialize new player
    pub fn init(id: PlayerId, initial_stack: ChipAmount) Self {
        return Self{
            .id = id,
            .stack = initial_stack,
            .initial_stack = initial_stack,
            .current_bet = 0,
            .total_bet = 0,
            .hole_cards = [_]Card{ 255, 255 }, // Invalid cards
            .has_cards = false,
            .is_active = true,
            .is_all_in = false,
            .is_sitting_out = false,
            .is_dealer = false,
            .is_small_blind = false,
            .is_big_blind = false,
            .is_turn = false,
            .has_acted_this_round = false,
            .last_action_aggressive = false,
        };
    }

    /// Reset for new hand (keep stack, reset everything else)
    pub fn newHand(self: *Self) void {
        self.current_bet = 0;
        self.total_bet = 0;
        self.hole_cards = [_]Card{ 255, 255 };
        self.has_cards = false;
        self.is_active = true;
        self.is_all_in = false;
        self.is_dealer = false;
        self.is_small_blind = false;
        self.is_big_blind = false;
        self.is_turn = false;
        self.has_acted_this_round = false;
        self.last_action_aggressive = false;
    }

    /// Reset betting for new round (keep hole cards and stack)
    pub fn resetBetting(self: *Self) void {
        self.current_bet = 0;
        self.has_acted_this_round = false;
        self.last_action_aggressive = false;
        self.is_turn = false;
    }

    /// Set hole cards for this hand
    pub fn setHoleCards(self: *Self, card1: Card, card2: Card) void {
        self.hole_cards[0] = card1;
        self.hole_cards[1] = card2;
        self.has_cards = true;
    }

    /// Place a bet (call, raise, blind, etc.)
    pub fn bet(self: *Self, amount: ChipAmount) !void {
        if (amount > self.stack) {
            return error.InsufficientChips;
        }

        if (!self.is_active) {
            return error.PlayerNotActive;
        }

        // Deduct from stack
        self.stack -= amount;
        self.current_bet += amount;
        self.total_bet += amount;
        self.has_acted_this_round = true;

        // Check if all-in
        if (self.stack == 0) {
            self.is_all_in = true;
        }

        // Mark as aggressive action if it's a raise
        // (This will be set by the caller for raises)
    }

    /// Fold hand
    pub fn fold(self: *Self) void {
        self.is_active = false;
        self.has_acted_this_round = true;
        self.last_action_aggressive = false;
        self.is_turn = false;
    }

    /// Check if player can take any action
    pub fn canAct(self: Self) bool {
        return self.is_active and !self.is_all_in and !self.is_sitting_out;
    }

    /// Check if player can call given amount
    pub fn canCall(self: Self, call_amount: ChipAmount) bool {
        return self.canAct() and call_amount <= self.stack;
    }

    /// Check if player can raise to given amount
    pub fn canRaise(self: Self, raise_amount: ChipAmount) bool {
        if (!self.canAct()) return false;

        const additional_needed = raise_amount - self.current_bet;
        return additional_needed <= self.stack and additional_needed > 0;
    }

    /// Check if player can check (no bet to call)
    pub fn canCheck(self: Self, current_bet: ChipAmount) bool {
        return self.canAct() and self.current_bet >= current_bet;
    }

    /// Get amount needed to call
    pub fn getCallAmount(self: Self, current_bet: ChipAmount) ChipAmount {
        if (current_bet <= self.current_bet) return 0;
        return @min(current_bet - self.current_bet, self.stack);
    }

    /// Get maximum raise amount
    pub fn getMaxRaise(self: Self, current_bet: ChipAmount) ChipAmount {
        if (!self.canAct()) return 0;

        const call_amount = self.getCallAmount(current_bet);
        return self.current_bet + call_amount + (self.stack - call_amount);
    }

    /// Get minimum raise amount (typically big blind or last raise increment)
    pub fn getMinRaise(self: Self, current_bet: ChipAmount, min_raise_increment: ChipAmount) ChipAmount {
        if (!self.canRaise(current_bet + min_raise_increment)) return 0;
        return current_bet + min_raise_increment;
    }

    /// Mark aggressive action (raise/bet)
    pub fn markAggressive(self: *Self) void {
        self.last_action_aggressive = true;
    }

    /// Get effective stack (for all-in calculations)
    pub fn getEffectiveStack(self: Self) ChipAmount {
        return self.stack + self.current_bet;
    }

    /// Get profit/loss for this hand
    pub fn getHandPnL(self: Self) i32 {
        return @as(i32, @intCast(self.stack)) - @as(i32, @intCast(self.initial_stack - self.total_bet));
    }

    /// Get total investment in pot
    pub fn getTotalInvestment(self: Self) ChipAmount {
        return self.total_bet;
    }

    /// Check if player has specific position
    pub fn hasPosition(self: Self, comptime position: enum { dealer, small_blind, big_blind }) bool {
        return switch (position) {
            .dealer => self.is_dealer,
            .small_blind => self.is_small_blind,
            .big_blind => self.is_big_blind,
        };
    }

    /// Set position for this hand
    pub fn setPosition(self: *Self, comptime position: enum { dealer, small_blind, big_blind }, value: bool) void {
        switch (position) {
            .dealer => self.is_dealer = value,
            .small_blind => self.is_small_blind = value,
            .big_blind => self.is_big_blind = value,
        }
    }

    /// Get readable status string
    pub fn getStatus(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var status_parts = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        defer status_parts.deinit();

        if (!self.is_active) {
            try status_parts.append(allocator, "FOLDED");
        } else if (self.is_all_in) {
            try status_parts.append(allocator, "ALL-IN");
        } else if (self.is_sitting_out) {
            try status_parts.append(allocator, "SITTING_OUT");
        } else {
            try status_parts.append(allocator, "ACTIVE");
        }

        if (self.is_dealer) try status_parts.append(allocator, "DEALER");
        if (self.is_small_blind) try status_parts.append(allocator, "SB");
        if (self.is_big_blind) try status_parts.append(allocator, "BB");
        if (self.is_turn) try status_parts.append(allocator, "TURN");

        // Join status parts with "|"
        var result = try std.ArrayList(u8).initCapacity(allocator, 0);
        defer result.deinit();

        for (status_parts.items, 0..) |part, i| {
            if (i > 0) try result.appendSlice("|");
            try result.appendSlice(part);
        }

        return result.toOwnedSlice(allocator);
    }

    /// Compare players by position for betting order
    pub fn compareByPosition(context: struct { dealer_pos: PlayerId, num_players: u8 }, a: Player, b: Player) bool {
        const seats_from_dealer_a = (a.id + context.num_players - context.dealer_pos) % context.num_players;
        const seats_from_dealer_b = (b.id + context.num_players - context.dealer_pos) % context.num_players;
        return seats_from_dealer_a < seats_from_dealer_b;
    }

    /// Check if hole cards are valid
    pub fn hasValidCards(self: Self) bool {
        return self.has_cards and self.hole_cards[0] != 255 and self.hole_cards[1] != 255;
    }

    /// Get hole cards (returns error if no valid cards)
    pub fn getHoleCards(self: Self) ![2]Card {
        if (!self.hasValidCards()) {
            return error.NoValidCards;
        }
        return self.hole_cards;
    }

    /// Reset to initial state (new session)
    pub fn reset(self: *Self, new_stack: ChipAmount) void {
        self.stack = new_stack;
        self.initial_stack = new_stack;
        self.newHand();
    }

    /// Player decision context for AI
    pub const DecisionContext = struct {
        pot_size: ChipAmount,
        num_active_players: u8,
        position_relative_to_dealer: u8,
        betting_round: u8,
        num_raises_this_round: u8,
        time_to_act_ms: u32,
    };

    /// Get decision context for AI agents
    pub fn getDecisionContext(self: Self, pot_size: ChipAmount, num_active_players: u8, dealer_pos: PlayerId, num_players: u8, betting_round: u8, num_raises: u8) DecisionContext {
        const position = (self.id + num_players - dealer_pos) % num_players;

        return DecisionContext{
            .pot_size = pot_size,
            .num_active_players = num_active_players,
            .position_relative_to_dealer = position,
            .betting_round = betting_round,
            .num_raises_this_round = num_raises,
            .time_to_act_ms = 30000, // Default 30 second timer
        };
    }
};

/// Helper functions for player management
/// Sort players by betting order (position relative to dealer)
pub fn sortPlayersByBettingOrder(players: []Player, dealer_pos: PlayerId, num_players: u8) void {
    const context = .{ .dealer_pos = dealer_pos, .num_players = num_players };
    std.sort.block(Player, players, context, Player.compareByPosition);
}

/// Count active players in array
pub fn countActivePlayers(players: []const Player) u8 {
    var count: u8 = 0;
    for (players) |player| {
        if (player.is_active) count += 1;
    }
    return count;
}

/// Count players who can act
pub fn countPlayersWhoCanAct(players: []const Player) u8 {
    var count: u8 = 0;
    for (players) |player| {
        if (player.canAct()) count += 1;
    }
    return count;
}

/// Find next active player after given position
pub fn findNextActivePlayer(players: []const Player, start_pos: PlayerId) ?PlayerId {
    const num_players = @as(u8, @intCast(players.len));
    var pos = (start_pos + 1) % num_players;
    var count: u8 = 0;

    while (count < num_players) {
        if (players[pos].canAct()) {
            return pos;
        }
        pos = (pos + 1) % num_players;
        count += 1;
    }

    return null;
}

/// Get total chips in play
pub fn getTotalChipsInPlay(players: []const Player) ChipAmount {
    var total: ChipAmount = 0;
    for (players) |player| {
        total += player.stack + player.total_bet;
    }
    return total;
}

/// Validate player consistency
pub fn validatePlayerState(player: Player) !void {
    if (player.is_all_in and player.stack > 0) {
        return error.AllInWithChips;
    }

    if (!player.is_active and player.canAct()) {
        return error.InactivePlayerCanAct;
    }

    if (player.current_bet > player.total_bet) {
        return error.CurrentBetExceedsTotal;
    }

    if (player.has_cards and (!player.hasValidCards())) {
        return error.InvalidCardState;
    }
}

// Unit tests
test "player initialization" {
    const testing = std.testing;

    var player = Player.init(0, 1000);
    try testing.expectEqual(@as(PlayerId, 0), player.id);
    try testing.expectEqual(@as(ChipAmount, 1000), player.stack);
    try testing.expect(player.is_active);
    try testing.expect(!player.is_all_in);
    try testing.expect(!player.hasValidCards());
}

test "betting mechanics" {
    const testing = std.testing;

    var player = Player.init(0, 1000);

    // Test normal bet
    try player.bet(100);
    try testing.expectEqual(@as(ChipAmount, 900), player.stack);
    try testing.expectEqual(@as(ChipAmount, 100), player.current_bet);
    try testing.expectEqual(@as(ChipAmount, 100), player.total_bet);

    // Test all-in
    try player.bet(900);
    try testing.expect(player.is_all_in);
    try testing.expectEqual(@as(ChipAmount, 0), player.stack);

    // Test insufficient chips
    try testing.expectError(error.InsufficientChips, player.bet(1));
}

test "position management" {
    const testing = std.testing;

    var player = Player.init(0, 1000);

    player.setPosition(.dealer, true);
    try testing.expect(player.hasPosition(.dealer));
    try testing.expect(!player.hasPosition(.small_blind));

    player.setPosition(.small_blind, true);
    try testing.expect(player.hasPosition(.small_blind));
}

test "card management" {
    const testing = std.testing;

    var player = Player.init(0, 1000);

    try testing.expect(!player.hasValidCards());

    player.setHoleCards(10, 23);
    try testing.expect(player.hasValidCards());

    const cards = try player.getHoleCards();
    try testing.expectEqual(@as(Card, 10), cards[0]);
    try testing.expectEqual(@as(Card, 23), cards[1]);
}

test "action validation" {
    const testing = std.testing;

    var player = Player.init(0, 1000);

    // Active player can act
    try testing.expect(player.canAct());
    try testing.expect(player.canCall(100));
    try testing.expect(player.canRaise(200));
    try testing.expect(player.canCheck(0));

    // Folded player cannot act
    player.fold();
    try testing.expect(!player.canAct());
    try testing.expect(!player.canCall(100));
    try testing.expect(!player.canRaise(200));
}

test "helper functions" {
    const testing = std.testing;

    var players = [_]Player{
        Player.init(0, 1000),
        Player.init(1, 1000),
        Player.init(2, 1000),
    };

    players[1].fold();

    try testing.expectEqual(@as(u8, 2), countActivePlayers(&players));
    try testing.expectEqual(@as(u8, 2), countPlayersWhoCanAct(&players));
    try testing.expectEqual(@as(ChipAmount, 3000), getTotalChipsInPlay(&players));
}
