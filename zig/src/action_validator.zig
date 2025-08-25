//! Action Validation System
//!
//! Comprehensive validation of player actions in Texas Hold'em
//! Ensures all actions comply with poker rules and game state
//!
//! Features:
//! - Legal action generation
//! - Action validation with detailed error reporting
//! - Bet sizing validation
//! - All-in scenario handling
//! - Limit/No-limit rule enforcement

const std = @import("std");
const player = @import("player.zig");
const betting = @import("betting.zig");

pub const ChipAmount = u32;
pub const PlayerId = u8;
pub const Player = player.Player;
pub const BettingManager = betting.BettingManager;

/// Action types (must match game_engine.zig)
pub const ActionType = enum(u8) {
    fold = 0,
    call = 1,
    raise = 2,
    check = 3,
    all_in = 4,
};

/// Game configuration for validation
pub const GameConfig = struct {
    small_blind: ChipAmount,
    big_blind: ChipAmount,
    ante: ChipAmount = 0,
    initial_stack: ChipAmount,
    max_raises_per_round: u8 = 3,
    is_limit: bool = true, // Limit vs No-limit Hold'em
    min_bet_multiplier: f32 = 2.0, // Minimum raise size (2x big blind)
    is_tournament: bool = false,
};

/// Validation result with detailed feedback
pub const ValidationResult = struct {
    is_valid: bool,
    error_code: ErrorCode,
    message: []const u8,
    suggested_actions: []const ActionType,
    min_raise_amount: ChipAmount,
    max_raise_amount: ChipAmount,
    call_amount: ChipAmount,

    pub const ErrorCode = enum {
        valid,
        player_not_active,
        player_all_in,
        insufficient_chips,
        invalid_bet_amount,
        raises_capped,
        out_of_turn,
        cannot_check,
        minimum_raise_not_met,
        maximum_raise_exceeded,
        invalid_action_type,
        player_already_acted,
        game_terminal,
    };

    pub fn valid(call_amount: ChipAmount, min_raise: ChipAmount, max_raise: ChipAmount) ValidationResult {
        return ValidationResult{
            .is_valid = true,
            .error_code = .valid,
            .message = "Action is valid",
            .suggested_actions = &[_]ActionType{},
            .min_raise_amount = min_raise,
            .max_raise_amount = max_raise,
            .call_amount = call_amount,
        };
    }

    pub fn invalid(error_code: ErrorCode, message: []const u8) ValidationResult {
        return ValidationResult{
            .is_valid = false,
            .error_code = error_code,
            .message = message,
            .suggested_actions = &[_]ActionType{},
            .min_raise_amount = 0,
            .max_raise_amount = 0,
            .call_amount = 0,
        };
    }
};

/// Comprehensive action validator
/// Action structure for validation
pub const ActionForValidation = struct {
    action_type: ActionType,
    amount: ChipAmount,
    player_id: PlayerId,
};

pub const ActionValidator = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .allocator = undefined, // Will be set when needed
        };
    }

    pub fn initWithAllocator(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Validate a specific action
    pub fn validateAction(
        self: Self,
        action: ActionForValidation,
        target_player: *const Player,
        all_players: []const Player,
        betting_manager: *const BettingManager,
        config: GameConfig,
    ) ValidationResult {
        _ = all_players;

        // Basic player state checks
        if (!target_player.is_active) {
            return ValidationResult.invalid(.player_not_active, "Player has folded and cannot act");
        }

        if (target_player.is_all_in and action.action_type != .fold) {
            return ValidationResult.invalid(.player_all_in, "Player is all-in and can only fold");
        }

        if (!target_player.canAct()) {
            return ValidationResult.invalid(.player_not_active, "Player cannot act in current state");
        }

        // Calculate current betting context
        const call_amount = self.calculateCallAmount(target_player, betting_manager);
        const min_raise = self.calculateMinRaise(target_player, betting_manager, config);
        const max_raise = self.calculateMaxRaise(target_player, betting_manager);

        // Validate specific action type
        switch (action.action_type) {
            .fold => return self.validateFold(target_player, call_amount, min_raise, max_raise),
            .call => return self.validateCall(target_player, call_amount, min_raise, max_raise, betting_manager),
            .check => return self.validateCheck(target_player, call_amount, min_raise, max_raise, betting_manager),
            .raise => return self.validateRaise(action.amount, target_player, call_amount, min_raise, max_raise, betting_manager, config),
            .all_in => return self.validateAllIn(target_player, call_amount, min_raise, max_raise, betting_manager),
        }
    }

    /// Get all legal actions for a player
    pub fn getLegalActions(
        self: Self,
        target_player: *const Player,
        all_players: []const Player,
        betting_manager: *const BettingManager,
        config: GameConfig,
    ) ![]ActionType {
        _ = all_players;

        var legal_actions = std.ArrayList(ActionType).init(self.allocator);
        // Don't defer deinit here - toOwnedSlice() transfers ownership to caller

        if (!target_player.canAct()) {
            // Return an empty owned slice for consistency
            return legal_actions.toOwnedSlice();
        }

        // Fold is always legal (except when already all-in)
        if (!target_player.is_all_in) {
            try legal_actions.append(.fold);
        }

        const call_amount = self.calculateCallAmount(target_player, betting_manager);
        const min_raise = self.calculateMinRaise(target_player, betting_manager, config);

        // Check if player can check
        if (call_amount == 0) {
            try legal_actions.append(.check);
        }

        // Check if player can call
        if (call_amount > 0 and target_player.canCall(call_amount)) {
            try legal_actions.append(.call);
        }

        // Check if player can raise
        if (!betting_manager.areRaisesCapped() and target_player.canRaise(min_raise)) {
            try legal_actions.append(.raise);
        }

        // All-in is always legal if player has chips
        if (target_player.stack > 0) {
            try legal_actions.append(.all_in);
        }

        return legal_actions.toOwnedSlice();
    }

    /// Validate fold action
    fn validateFold(
        self: Self,
        target_player: *const Player,
        call_amount: ChipAmount,
        min_raise: ChipAmount,
        max_raise: ChipAmount,
    ) ValidationResult {
        _ = self;

        // Fold is always valid for active players
        if (target_player.is_active) {
            return ValidationResult.valid(call_amount, min_raise, max_raise);
        }

        return ValidationResult.invalid(.player_not_active, "Inactive player cannot fold");
    }

    /// Validate call action
    fn validateCall(
        self: Self,
        target_player: *const Player,
        call_amount: ChipAmount,
        min_raise: ChipAmount,
        max_raise: ChipAmount,
        betting_manager: *const BettingManager,
    ) ValidationResult {
        _ = self;
        _ = betting_manager;

        if (call_amount == 0) {
            return ValidationResult.invalid(.cannot_check, "No bet to call - use check instead");
        }

        if (!target_player.canCall(call_amount)) {
            return ValidationResult.invalid(.insufficient_chips, "Insufficient chips to call");
        }

        return ValidationResult.valid(call_amount, min_raise, max_raise);
    }

    /// Validate check action
    fn validateCheck(
        self: Self,
        target_player: *const Player,
        call_amount: ChipAmount,
        min_raise: ChipAmount,
        max_raise: ChipAmount,
        betting_manager: *const BettingManager,
    ) ValidationResult {
        _ = self;

        if (call_amount > 0) {
            return ValidationResult.invalid(.cannot_check, "Cannot check when there is a bet to call");
        }

        if (!target_player.canCheck(betting_manager.current_bet)) {
            return ValidationResult.invalid(.cannot_check, "Player has not matched current bet");
        }

        return ValidationResult.valid(call_amount, min_raise, max_raise);
    }

    /// Validate raise action
    fn validateRaise(
        self: Self,
        raise_amount: ChipAmount,
        target_player: *const Player,
        call_amount: ChipAmount,
        min_raise: ChipAmount,
        max_raise: ChipAmount,
        betting_manager: *const BettingManager,
        config: GameConfig,
    ) ValidationResult {
        _ = self;

        if (betting_manager.areRaisesCapped()) {
            return ValidationResult.invalid(.raises_capped, "Maximum raises reached for this round");
        }

        if (raise_amount < min_raise) {
            return ValidationResult.invalid(.minimum_raise_not_met, "Raise amount below minimum");
        }

        if (raise_amount > max_raise) {
            return ValidationResult.invalid(.maximum_raise_exceeded, "Raise amount exceeds maximum");
        }

        if (!target_player.canRaise(raise_amount)) {
            return ValidationResult.invalid(.insufficient_chips, "Insufficient chips to raise");
        }

        // Additional limit hold'em checks
        if (config.is_limit) {
            const expected_raise = if (betting_manager.current_round == .pre_flop or betting_manager.current_round == .flop)
                config.big_blind
            else
                config.big_blind * 2;

            if (raise_amount != betting_manager.current_bet + expected_raise) {
                return ValidationResult.invalid(.invalid_bet_amount, "Invalid raise amount for limit hold'em");
            }
        }

        return ValidationResult.valid(call_amount, min_raise, max_raise);
    }

    /// Validate all-in action
    fn validateAllIn(
        self: Self,
        target_player: *const Player,
        call_amount: ChipAmount,
        min_raise: ChipAmount,
        max_raise: ChipAmount,
        betting_manager: *const BettingManager,
    ) ValidationResult {
        _ = self;
        _ = betting_manager;

        if (target_player.stack == 0) {
            return ValidationResult.invalid(.insufficient_chips, "Player has no chips to go all-in");
        }

        // All-in is always valid if player has chips
        return ValidationResult.valid(call_amount, min_raise, max_raise);
    }

    // Helper calculation methods

    fn calculateCallAmount(self: Self, target_player: *const Player, betting_manager: *const BettingManager) ChipAmount {
        _ = self;

        if (betting_manager.current_bet <= target_player.current_bet) {
            return 0;
        }

        const needed = betting_manager.current_bet - target_player.current_bet;
        return @min(needed, target_player.stack);
    }

    fn calculateMinRaise(self: Self, target_player: *const Player, betting_manager: *const BettingManager, config: GameConfig) ChipAmount {
        _ = self;
        _ = target_player;

        if (config.is_limit) {
            // Limit hold'em: fixed raise amounts
            const base_bet = if (betting_manager.current_round == .pre_flop or betting_manager.current_round == .flop)
                config.big_blind
            else
                config.big_blind * 2;

            return betting_manager.current_bet + base_bet;
        } else {
            // No-limit: minimum raise is the size of the last raise or big blind
            const min_raise_size = @max(betting_manager.getMinRaiseAmount(), config.big_blind);
            return betting_manager.current_bet + min_raise_size;
        }
    }

    fn calculateMaxRaise(self: Self, target_player: *const Player, betting_manager: *const BettingManager) ChipAmount {
        _ = self;
        _ = betting_manager;

        // Maximum is all-in amount
        return target_player.current_bet + target_player.stack;
    }

    /// Validate betting sequence for round
    pub fn validateBettingSequence(
        self: Self,
        actions: []const ActionType,
        players: []const Player,
        betting_manager: *const BettingManager,
        config: GameConfig,
    ) !ValidationResult {
        _ = self;
        _ = actions;
        _ = players;
        _ = betting_manager;
        _ = config;

        // TODO: Implement sequence validation
        // This would check that the sequence of actions makes sense
        // For example: raise -> call -> call is valid
        // But raise -> raise -> raise -> raise might not be (if capped)

        return ValidationResult.valid(0, 0, 0);
    }

    /// Get suggested actions based on game state
    pub fn getSuggestedActions(
        self: Self,
        target_player: *const Player,
        betting_manager: *const BettingManager,
        pot_size: ChipAmount,
        config: GameConfig,
    ) ![]ActionType {
        var suggestions = std.ArrayList(ActionType).init(self.allocator);
        defer suggestions.deinit();

        const call_amount = self.calculateCallAmount(target_player, betting_manager);
        const pot_odds = if (call_amount > 0) @as(f32, @floatFromInt(pot_size)) / @as(f32, @floatFromInt(call_amount)) else 0;

        // Basic strategy suggestions based on pot odds
        if (pot_odds > 3.0) { // Good pot odds
            if (call_amount > 0) {
                try suggestions.append(.call);
            } else {
                try suggestions.append(.check);
            }
        }

        if (target_player.stack > config.big_blind * 10) { // Deep stack
            if (!betting_manager.areRaisesCapped()) {
                try suggestions.append(.raise);
            }
        }

        // Always suggest fold as an option
        try suggestions.append(.fold);

        return suggestions.toOwnedSlice();
    }

    /// Check if action sequence indicates aggressive play
    pub fn isAggressiveSequence(self: Self, actions: []const ActionType) bool {
        _ = self;

        var aggressive_count: u32 = 0;
        for (actions) |action| {
            if (action == .raise or action == .all_in) {
                aggressive_count += 1;
            }
        }

        return aggressive_count > actions.len / 2;
    }

    /// Calculate expected value of an action (simplified)
    pub fn calculateActionEV(
        self: Self,
        action_type: ActionType,
        target_player: *const Player,
        pot_size: ChipAmount,
        estimated_win_probability: f32,
    ) f32 {
        _ = self;

        switch (action_type) {
            .fold => return 0.0,
            .call => {
                const call_amount = @as(f32, @floatFromInt(target_player.current_bet));
                const pot_value = @as(f32, @floatFromInt(pot_size));
                return estimated_win_probability * pot_value - call_amount;
            },
            .check => return estimated_win_probability * @as(f32, @floatFromInt(pot_size)),
            .raise => {
                // Simplified: assume raise has 10% higher win rate due to fold equity
                const adjusted_win_prob = @min(1.0, estimated_win_probability * 1.1);
                const raise_amount = @as(f32, @floatFromInt(target_player.stack)) * 0.5; // Assume 50% stack raise
                const pot_value = @as(f32, @floatFromInt(pot_size));
                return adjusted_win_prob * (pot_value + raise_amount) - raise_amount;
            },
            .all_in => {
                // High risk, high reward
                const adjusted_win_prob = @min(1.0, estimated_win_probability * 1.2);
                const all_in_amount = @as(f32, @floatFromInt(target_player.stack));
                const pot_value = @as(f32, @floatFromInt(pot_size));
                return adjusted_win_prob * (pot_value + all_in_amount) - all_in_amount;
            },
        }
    }
};

// Unit tests
test "action validator initialization" {
    const testing = std.testing;

    var validator = ActionValidator.initWithAllocator(testing.allocator);

    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
    };

    var player_test = Player.init(0, 1000);
    var betting_manager = BettingManager.initWithAllocator(testing.allocator);
    defer betting_manager.deinit();

    // Test basic validation
    const fold_action = ActionForValidation{ .action_type = ActionType.fold, .amount = 0, .player_id = 0 };
    const result = validator.validateAction(fold_action, &player_test, &[_]Player{player_test}, &betting_manager, config);

    try testing.expect(result.is_valid);
}

test "call amount calculation" {
    const testing = std.testing;

    var validator = ActionValidator.initWithAllocator(testing.allocator);
    var player_test = Player.init(0, 1000);
    var betting_manager = BettingManager.initWithAllocator(testing.allocator);
    defer betting_manager.deinit();

    betting_manager.current_bet = 100;
    player_test.current_bet = 50;

    const call_amount = validator.calculateCallAmount(&player_test, &betting_manager);
    try testing.expectEqual(@as(ChipAmount, 50), call_amount);
}

test "legal actions generation" {
    const testing = std.testing;

    var validator = ActionValidator.initWithAllocator(testing.allocator);
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
    };

    var player_test = Player.init(0, 1000);
    var betting_manager = BettingManager.initWithAllocator(testing.allocator);
    defer betting_manager.deinit();

    const legal_actions = try validator.getLegalActions(&player_test, &[_]Player{player_test}, &betting_manager, config);
    defer testing.allocator.free(legal_actions);

    try testing.expect(legal_actions.len > 0);

    // Should include fold, check (no bet), and all-in
    var has_fold = false;
    var has_check = false;
    for (legal_actions) |action| {
        if (action == .fold) has_fold = true;
        if (action == .check) has_check = true;
    }

    try testing.expect(has_fold);
    try testing.expect(has_check);
}
