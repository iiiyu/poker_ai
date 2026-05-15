//! Texas Hold'em Game Engine
//!
//! High-performance, memory-efficient implementation of Texas Hold'em poker rules
//! Compatible with Python implementation for MCCFR training
//!
//! Key features:
//! - Zero heap allocations in hot paths
//! - Stack-based state representation
//! - Compile-time validation
//! - Support for 2-8 players
//! - Thread-safe for parallel training

const std = @import("std");
const config = @import("config.zig");
const player = @import("player.zig");
const pot = @import("pot.zig");
const betting = @import("betting.zig");
const action_validator = @import("action_validator.zig");

pub const Card = u8; // 0-51 representation
pub const PlayerId = u8;
pub const ChipAmount = u32;

/// Betting rounds in Texas Hold'em
pub const BettingStage = enum(u8) {
    pre_flop = 0,
    flop = 1,
    turn = 2,
    river = 3,
    show_down = 4,
    terminal = 5,

    pub fn next(self: BettingStage) ?BettingStage {
        return switch (self) {
            .pre_flop => .flop,
            .flop => .turn,
            .turn => .river,
            .river => .show_down,
            .show_down => .terminal,
            .terminal => null,
        };
    }

    pub fn boardSize(self: BettingStage) u8 {
        return switch (self) {
            .pre_flop => 0,
            .flop => 3,
            .turn => 4,
            .river => 5,
            .show_down => 5,
            .terminal => 5,
        };
    }

    pub fn toString(self: BettingStage) []const u8 {
        return switch (self) {
            .pre_flop => "pre_flop",
            .flop => "flop",
            .turn => "turn",
            .river => "river",
            .show_down => "show_down",
            .terminal => "terminal",
        };
    }
};

/// Player action types (matches Python implementation)
pub const ActionType = enum(u8) {
    fold = 0,
    call = 1,
    raise = 2,
    check = 3,
    all_in = 4,

    pub fn toString(self: ActionType) []const u8 {
        return switch (self) {
            .fold => "fold",
            .call => "call",
            .raise => "raise",
            .check => "check",
            .all_in => "all_in",
        };
    }
};

/// Complete player action with amount
pub const Action = struct {
    action_type: ActionType,
    amount: ChipAmount,
    player_id: PlayerId,

    pub fn fold(player_id: PlayerId) Action {
        return Action{ .action_type = .fold, .amount = 0, .player_id = player_id };
    }

    pub fn call(player_id: PlayerId) Action {
        return Action{ .action_type = .call, .amount = 0, .player_id = player_id };
    }

    pub fn check(player_id: PlayerId) Action {
        return Action{ .action_type = .check, .amount = 0, .player_id = player_id };
    }

    pub fn raise(player_id: PlayerId, amount: ChipAmount) Action {
        return Action{ .action_type = .raise, .amount = amount, .player_id = player_id };
    }

    pub fn allIn(player_id: PlayerId, amount: ChipAmount) Action {
        return Action{ .action_type = .all_in, .amount = amount, .player_id = player_id };
    }

    pub fn isAggressive(self: Action) bool {
        return self.action_type == .raise or self.action_type == .all_in;
    }

    pub fn toString(self: Action, allocator: std.mem.Allocator) ![]u8 {
        if (self.amount > 0) {
            return std.fmt.allocPrint(allocator, "{s}:{d}", .{ self.action_type.toString(), self.amount });
        } else {
            return std.fmt.allocPrint(allocator, "{s}", .{self.action_type.toString()});
        }
    }
};

/// Maximum number of players supported
pub const MAX_PLAYERS = config.MAX_PLAYERS;
pub const MIN_PLAYERS = config.MIN_PLAYERS;

/// Game configuration
pub const GameConfig = struct {
    small_blind: ChipAmount,
    big_blind: ChipAmount,
    ante: ChipAmount = 0,
    initial_stack: ChipAmount,
    max_raises_per_round: u8 = 3, // Limit Hold'em style
};

/// Complete Texas Hold'em game state
pub const TexasHoldemGameEngine = struct {
    // Core game state
    players: [MAX_PLAYERS]player.Player,
    num_players: u8,
    active_players: u8,

    // Table state
    board: [5]Card,
    board_size: u8,
    betting_stage: BettingStage,

    // Betting state
    current_player_index: u8,
    dealer_button: PlayerId,
    small_blind_position: PlayerId,
    big_blind_position: PlayerId,

    // Pot management
    pot_manager: pot.PotManager,

    // Betting round management
    betting_manager: betting.BettingManager,

    // Action validation
    action_validator: action_validator.ActionValidator,

    // Game configuration
    config: GameConfig,

    // Action history for information sets
    action_history: std.ArrayList(Action),

    // State flags
    is_terminal: bool,

    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new Texas Hold'em game
    pub fn init(allocator: std.mem.Allocator, num_players: u8, game_config: GameConfig) !Self {
        if (num_players < MIN_PLAYERS or num_players > MAX_PLAYERS) {
            return error.InvalidPlayerCount;
        }

        var engine = Self{
            .players = undefined,
            .num_players = num_players,
            .active_players = num_players,
            .board = [_]Card{255} ** 5, // Invalid card marker
            .board_size = 0,
            .betting_stage = .pre_flop,
            .current_player_index = 0,
            .dealer_button = 0,
            .small_blind_position = 1,
            .big_blind_position = 2,
            .pot_manager = pot.PotManager.init(allocator),
            .betting_manager = betting.BettingManager.init(),
            .action_validator = action_validator.ActionValidator.initWithAllocator(allocator),
            .config = game_config,
            .action_history = std.ArrayList(Action){},
            .is_terminal = false,
            .allocator = allocator,
        };

        // Initialize players
        for (0..num_players) |i| {
            engine.players[i] = player.Player.init(@intCast(i), game_config.initial_stack);
        }

        // Set blinds and dealer positions for heads-up vs multi-player
        if (num_players == 2) {
            // Heads-up: dealer is small blind
            engine.small_blind_position = 0;
            engine.big_blind_position = 1;
        } else {
            // Multi-player: positions relative to dealer
            engine.small_blind_position = 1;
            engine.big_blind_position = 2;
        }

        return engine;
    }

    pub fn deinit(self: *Self) void {
        self.pot_manager.deinit();
        self.action_history.deinit(self.allocator);
    }

    /// Start a new hand (reset for next hand)
    pub fn newHand(self: *Self) !void {
        // Reset players for new hand
        for (self.players[0..self.num_players]) |*p| {
            p.newHand();
        }

        // Reset game state
        self.board = [_]Card{255} ** 5;
        self.board_size = 0;
        self.betting_stage = .pre_flop;
        self.active_players = self.num_players;
        self.is_terminal = false;

        // Clear history
        self.action_history.clearRetainingCapacity();

        // Reset managers
        self.pot_manager.reset();
        self.betting_manager.reset();

        // Rotate dealer button
        self.dealer_button = (self.dealer_button + 1) % self.num_players;

        // Update blind positions
        if (self.num_players == 2) {
            self.small_blind_position = self.dealer_button;
            self.big_blind_position = (self.dealer_button + 1) % self.num_players;
        } else {
            self.small_blind_position = (self.dealer_button + 1) % self.num_players;
            self.big_blind_position = (self.dealer_button + 2) % self.num_players;
        }

        // Post blinds
        try self.postBlinds();

        // Set first to act for preflop
        self.current_player_index = self.nextActivePlayer(self.big_blind_position);

        // Initialize betting round
        try self.betting_manager.startRound(self.players[0..self.num_players], self.current_player_index, self.config.big_blind);
    }

    /// Deal hole cards to all players
    pub fn dealHoleCards(self: *Self, hands: []const [2]Card) !void {
        if (hands.len != self.num_players) {
            return error.InvalidHandCount;
        }

        for (hands, 0..) |hand, i| {
            if (i < self.num_players) {
                self.players[i].setHoleCards(hand[0], hand[1]);
            }
        }
    }

    /// Deal community cards for current stage
    pub fn dealCommunityCards(self: *Self, cards: []const Card) !void {
        const expected_cards: usize = switch (self.betting_stage) {
            .pre_flop => return error.CannotDealCardsPreflop,
            .flop => 3,
            .turn => 1,
            .river => 1,
            .show_down, .terminal => return error.CannotDealCardsAfterRiver,
        };

        if (cards.len != expected_cards) {
            return error.InvalidCardCount;
        }

        const start_index = self.board_size;
        for (cards, 0..) |card, i| {
            self.board[start_index + i] = card;
        }
        self.board_size += @intCast(cards.len);
    }

    /// Apply a player action and advance game state
    pub fn applyAction(self: *Self, action: Action) !void {
        // Convert Action to ActionForValidation
        const validation_action = action_validator.ActionForValidation{
            .action_type = @enumFromInt(@intFromEnum(action.action_type)),
            .amount = action.amount,
            .player_id = action.player_id,
        };

        // Convert GameConfig for validation
        const validator_config = action_validator.GameConfig{
            .small_blind = self.config.small_blind,
            .big_blind = self.config.big_blind,
            .ante = self.config.ante,
            .initial_stack = self.config.initial_stack,
            .max_raises_per_round = self.config.max_raises_per_round,
            .is_limit = false,
            .min_bet_multiplier = 2.0,
            .is_tournament = false,
        };

        // Validate action
        const validation_result = self.action_validator.validateAction(validation_action, &self.players[action.player_id], self.players[0..self.num_players], &self.betting_manager, validator_config);

        if (!validation_result.is_valid) {
            return error.InvalidAction;
        }

        // Apply action to player and pot
        switch (action.action_type) {
            .fold => {
                self.players[action.player_id].fold();
                self.active_players -= 1;
            },
            .call => {
                const call_amount = self.betting_manager.getCallAmount(action.player_id);
                try self.players[action.player_id].bet(call_amount);
                try self.pot_manager.addToPot(call_amount, action.player_id);
            },
            .check => {
                // No chips to move for check
            },
            .raise => {
                const total_bet = action.amount;
                const current_bet = self.players[action.player_id].current_bet;
                const additional = total_bet - current_bet;

                try self.players[action.player_id].bet(additional);
                try self.pot_manager.addToPot(additional, action.player_id);
                self.betting_manager.registerRaise(action.player_id, total_bet);
            },
            .all_in => {
                const all_in_amount = self.players[action.player_id].stack;
                try self.players[action.player_id].bet(all_in_amount);
                try self.pot_manager.addToPot(all_in_amount, action.player_id);

                const total_bet = self.players[action.player_id].current_bet;
                if (total_bet > self.betting_manager.current_bet) {
                    self.betting_manager.registerRaise(action.player_id, total_bet);
                }
            },
        }

        // Record action in history
        try self.action_history.append(self.allocator, action);

        // Update betting manager
        self.betting_manager.recordAction(.{
            .action_type = @intFromEnum(action.action_type),
            .player_id = action.player_id,
            .amount = action.amount,
        });

        // Check if betting round is complete
        if (self.isBettingRoundComplete()) {
            try self.advanceToNextStage();
        } else {
            // Move to next player
            self.current_player_index = self.nextActivePlayer(self.current_player_index);
        }

        // Check terminal conditions
        self.updateTerminalState();
    }

    /// Get legal actions for current player
    pub fn getLegalActions(self: Self) ![]ActionType {
        const current_player = &self.players[self.current_player_index];

        // Convert GameConfig to ActionValidator's GameConfig
        const validator_config = action_validator.GameConfig{
            .small_blind = self.config.small_blind,
            .big_blind = self.config.big_blind,
            .ante = self.config.ante,
            .initial_stack = self.config.initial_stack,
            .max_raises_per_round = self.config.max_raises_per_round,
            .is_limit = false, // Assume No-limit for now
            .min_bet_multiplier = 2.0,
            .is_tournament = false,
        };

        const validator_actions = try self.action_validator.getLegalActions(current_player, self.players[0..self.num_players], &self.betting_manager, validator_config);

        // Convert ActionValidator.ActionType to game_engine.ActionType
        const converted_actions = try self.allocator.alloc(ActionType, validator_actions.len);
        for (validator_actions, 0..) |validator_action, i| {
            converted_actions[i] = @enumFromInt(@intFromEnum(validator_action));
        }

        // We must defer the deallocation of validator_actions
        defer self.allocator.free(validator_actions);

        return converted_actions;
    }

    /// Get information set string for given player (for MCCFR)
    pub fn getInfoSet(self: Self, player_id: PlayerId) ![]u8 {
        var info_set = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        errdefer info_set.deinit(self.allocator);

        const target_player = &self.players[player_id];

        // Add hole cards
        try info_set.append(self.allocator, target_player.hole_cards[0]);
        try info_set.append(self.allocator, target_player.hole_cards[1]);

        // Add community cards
        for (self.board[0..self.board_size]) |card| {
            try info_set.append(self.allocator, card);
        }

        // Add betting stage
        try info_set.append(self.allocator, @intFromEnum(self.betting_stage));

        // Add compressed action history
        for (self.action_history.items) |action| {
            try info_set.append(self.allocator, @intFromEnum(action.action_type));
        }

        return info_set.toOwnedSlice(self.allocator);
    }

    /// Get current pot size
    pub fn getPotSize(self: Self) ChipAmount {
        return self.pot_manager.getTotalPot();
    }

    /// Get payout for each player (for terminal states)
    pub fn getPayouts(self: Self) ![MAX_PLAYERS]i32 {
        if (!self.is_terminal) {
            return error.GameNotTerminal;
        }

        return self.pot_manager.calculatePayouts(self.players[0..self.num_players]);
    }

    /// Check if game is in terminal state
    pub fn isGameTerminal(self: Self) bool {
        return self.is_terminal;
    }

    /// Get current betting stage
    pub fn getCurrentStage(self: Self) BettingStage {
        return self.betting_stage;
    }

    /// Get current player
    pub fn getCurrentPlayer(self: Self) PlayerId {
        return self.current_player_index;
    }

    // Private helper methods

    fn postBlinds(self: *Self) !void {
        // Small blind
        const sb_player = &self.players[self.small_blind_position];
        const sb_amount = @min(self.config.small_blind, sb_player.stack);
        try sb_player.bet(sb_amount);
        try self.pot_manager.addToPot(sb_amount, self.small_blind_position);

        // Big blind
        const bb_player = &self.players[self.big_blind_position];
        const bb_amount = @min(self.config.big_blind, bb_player.stack);
        try bb_player.bet(bb_amount);
        try self.pot_manager.addToPot(bb_amount, self.big_blind_position);
    }

    fn isBettingRoundComplete(self: Self) bool {
        return self.betting_manager.isRoundComplete(self.players[0..self.num_players]);
    }

    fn advanceToNextStage(self: *Self) !void {
        if (self.betting_stage.next()) |next_stage| {
            self.betting_stage = next_stage;

            // Reset betting for new round
            for (self.players[0..self.num_players]) |*p| {
                p.resetBetting();
            }

            // Start new betting round
            self.current_player_index = self.nextActivePlayer(self.dealer_button);
            try self.betting_manager.startRound(self.players[0..self.num_players], self.current_player_index, 0 // No forced bet except blinds
            );
        } else {
            self.is_terminal = true;
        }
    }

    fn nextActivePlayer(self: Self, start: PlayerId) PlayerId {
        var next = (start + 1) % self.num_players;
        var count: u8 = 0;

        while (count < self.num_players) {
            if (self.players[next].is_active and self.players[next].canAct()) {
                return next;
            }
            next = (next + 1) % self.num_players;
            count += 1;
        }

        return start; // Fallback to start position
    }

    fn updateTerminalState(self: *Self) void {
        // Game is terminal if only one active player or showdown complete
        if (self.active_players <= 1) {
            self.is_terminal = true;
        } else if (self.betting_stage == .show_down and self.isBettingRoundComplete()) {
            self.is_terminal = true;
        }
    }
};

// Unit tests
test "game engine initialization" {
    const testing = std.testing;

    const game_config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
    };

    var engine = try TexasHoldemGameEngine.init(testing.allocator, 6, game_config);
    defer engine.deinit();

    try testing.expectEqual(@as(u8, 6), engine.num_players);
    try testing.expectEqual(BettingStage.pre_flop, engine.betting_stage);
    try testing.expectEqual(@as(u32, 5), engine.config.small_blind);
    try testing.expectEqual(@as(u32, 10), engine.config.big_blind);
}

test "action creation and validation" {
    const testing = std.testing;

    const fold_action = Action.fold(0);
    try testing.expectEqual(ActionType.fold, fold_action.action_type);
    try testing.expectEqual(@as(u32, 0), fold_action.amount);
    try testing.expectEqual(@as(u8, 0), fold_action.player_id);

    const raise_action = Action.raise(1, 100);
    try testing.expectEqual(ActionType.raise, raise_action.action_type);
    try testing.expectEqual(@as(u32, 100), raise_action.amount);
    try testing.expect(raise_action.isAggressive());
}

test "betting stage progression" {
    const testing = std.testing;

    try testing.expectEqual(BettingStage.flop, BettingStage.pre_flop.next().?);
    try testing.expectEqual(BettingStage.turn, BettingStage.flop.next().?);
    try testing.expectEqual(BettingStage.river, BettingStage.turn.next().?);
    try testing.expectEqual(BettingStage.show_down, BettingStage.river.next().?);
    try testing.expectEqual(@as(?BettingStage, null), BettingStage.terminal.next());
}
