// Texas Hold'em game state representation
// Efficient representation optimized for CFR algorithm

const std = @import("std");
const hand_eval = @import("hand_eval.zig");

// Card representation (0-51)
pub const Card = u8;

// Player's hole cards
pub const Hand = struct {
    cards: [2]Card,

    pub fn init(card1: Card, card2: Card) Hand {
        return Hand{ .cards = .{ card1, card2 } };
    }

    pub fn isEmpty(self: Hand) bool {
        return self.cards[0] == 255 and self.cards[1] == 255;
    }
};

// Player action types
pub const ActionType = enum(u8) {
    fold = 0,
    call = 1,
    raise = 2,
    check = 3,
    all_in = 4,
};

// Player action with amount
pub const Action = struct {
    action_type: ActionType,
    amount: u32, // Bet/raise amount (0 for fold/call/check)

    pub fn fold() Action {
        return Action{ .action_type = .fold, .amount = 0 };
    }

    pub fn call() Action {
        return Action{ .action_type = .call, .amount = 0 };
    }

    pub fn check() Action {
        return Action{ .action_type = .check, .amount = 0 };
    }

    pub fn raise(amount: u32) Action {
        return Action{ .action_type = .raise, .amount = amount };
    }

    pub fn allIn(amount: u32) Action {
        return Action{ .action_type = .all_in, .amount = amount };
    }

    pub fn isAgressive(self: Action) bool {
        return self.action_type == .raise or self.action_type == .all_in;
    }
};

// Betting round
pub const Round = enum(u8) {
    preflop = 0,
    flop = 1,
    turn = 2,
    river = 3,

    pub fn next(self: Round) ?Round {
        return switch (self) {
            .preflop => .flop,
            .flop => .turn,
            .turn => .river,
            .river => null,
        };
    }

    pub fn boardSize(self: Round) u8 {
        return switch (self) {
            .preflop => 0,
            .flop => 3,
            .turn => 4,
            .river => 5,
        };
    }
};

// Player state
pub const Player = struct {
    id: u8,
    stack: u32,
    hand: Hand,
    is_active: bool,
    is_all_in: bool,
    bet_this_round: u32,
    total_bet: u32,

    pub fn init(id: u8, stack: u32) Player {
        return Player{
            .id = id,
            .stack = stack,
            .hand = Hand{ .cards = .{ 255, 255 } }, // Empty hand
            .is_active = true,
            .is_all_in = false,
            .bet_this_round = 0,
            .total_bet = 0,
        };
    }

    pub fn fold(self: *Player) void {
        self.is_active = false;
    }

    pub fn bet(self: *Player, amount: u32) bool {
        if (amount > self.stack) return false;

        self.stack -= amount;
        self.bet_this_round += amount;
        self.total_bet += amount;

        if (self.stack == 0) {
            self.is_all_in = true;
        }

        return true;
    }

    pub fn canAct(self: Player) bool {
        return self.is_active and !self.is_all_in;
    }
};

// Complete game state
pub const GameState = struct {
    // Players
    players: [6]Player,
    num_players: u8,
    active_players: u8,

    // Game state
    round: Round,
    board: [5]Card,
    board_size: u8,
    
    // Deck position for deterministic card dealing in MCCFR
    deck_position: u8,
    deck: [52]Card,

    // Betting state
    current_player: u8,
    dealer_button: u8,
    small_blind: u32,
    big_blind: u32,
    pot: u32,
    current_bet: u32,
    last_raiser: ?u8,

    // Action history
    actions: std.ArrayList(Action),
    action_sequence: std.ArrayList(u8), // Compact sequence for abstractions

    // Storage for legal actions
    legal_actions_buffer: [5]Action,
    legal_actions_count: usize,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, num_players: u8, small_blind: u32, big_blind: u32) !Self {
        var state = Self{
            .players = undefined,
            .num_players = num_players,
            .active_players = num_players,
            .round = .preflop,
            .board = .{ 255, 255, 255, 255, 255 },
            .board_size = 0,
            .deck_position = 0,
            .deck = undefined,
            .current_player = 0,
            .dealer_button = 0,
            .small_blind = small_blind,
            .big_blind = big_blind,
            .pot = 0,
            .current_bet = 0,
            .last_raiser = null,
            .actions = std.ArrayList(Action).init(allocator),
            .action_sequence = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
            .legal_actions_buffer = undefined,
            .legal_actions_count = 0,
        };

        // Initialize players
        for (state.players[0..num_players], 0..) |*player, i| {
            player.* = Player.init(@intCast(i), 1000); // Default stack
        }
        
        // Initialize deck
        for (0..52) |i| {
            state.deck[i] = @intCast(i);
        }

        return state;
    }

    pub fn deinit(self: *Self) void {
        self.actions.deinit();
        self.action_sequence.deinit();
    }

    // Post blinds to start the betting round
    pub fn postBlinds(self: *Self) !void {
        // Small blind position (left of dealer)
        const sb_pos = (self.dealer_button + 1) % self.num_players;
        // Big blind position (left of small blind)
        const bb_pos = (self.dealer_button + 2) % self.num_players;

        // Post small blind
        var sb_player = &self.players[sb_pos];
        if (!sb_player.bet(self.small_blind)) return error.InsufficientStack;
        self.pot += self.small_blind;

        // Post big blind
        var bb_player = &self.players[bb_pos];
        if (!bb_player.bet(self.big_blind)) return error.InsufficientStack;
        self.pot += self.big_blind;
        self.current_bet = self.big_blind;

        // Set current player to left of big blind
        self.current_player = (bb_pos + 1) % self.num_players;
    }

    // Deal hole cards to players
    pub fn dealHoleCards(self: *Self, hands: [][2]Card) void {
        for (hands, 0..) |hand, i| {
            if (i < self.num_players) {
                self.players[i].hand = Hand.init(hand[0], hand[1]);
            }
        }
    }

    // Deal board cards for current round
    pub fn dealBoard(self: *Self, cards: []const Card) void {
        const board_start = self.round.boardSize();
        const new_cards: u8 = switch (self.round) {
            .preflop => 0,
            .flop => 3,
            .turn => 1,
            .river => 1,
        };

        for (cards[0..new_cards], 0..) |card, i| {
            self.board[board_start + i] = card;
        }

        self.board_size = self.round.boardSize() + new_cards;
    }

    // Apply player action
    pub fn applyAction(self: *Self, action: Action) !bool {
        const player = &self.players[self.current_player];

        if (!player.canAct()) return false;

        switch (action.action_type) {
            .fold => {
                player.fold();
                self.active_players -= 1;
            },
            .call => {
                const call_amount = self.current_bet - player.bet_this_round;
                if (!player.bet(call_amount)) return false;
                self.pot += call_amount;
            },
            .check => {
                if (self.current_bet > player.bet_this_round) return false;
            },
            .raise => {
                const total_amount = action.amount + self.current_bet;
                const additional = total_amount - player.bet_this_round;
                if (!player.bet(additional)) return false;

                self.pot += additional;
                self.current_bet = total_amount;
                self.last_raiser = self.current_player;
            },
            .all_in => {
                const all_in_amount = player.stack;
                if (!player.bet(all_in_amount)) return false;

                self.pot += all_in_amount;
                if (player.bet_this_round > self.current_bet) {
                    self.current_bet = player.bet_this_round;
                    self.last_raiser = self.current_player;
                }
            },
        }

        // Record action
        try self.actions.append(action);
        try self.action_sequence.append(@intFromEnum(action.action_type));

        // Move to next player
        self.advanceToNextPlayer();

        return true;
    }

    // Check if betting round is complete
    pub fn isBettingComplete(self: Self) bool {
        if (self.active_players <= 1) return true;

        var active_count: u8 = 0;
        var players_acted: u8 = 0;

        for (self.players[0..self.num_players]) |player| {
            if (player.is_active) {
                active_count += 1;
                if (player.bet_this_round == self.current_bet or player.is_all_in) {
                    players_acted += 1;
                }
            }
        }

        return players_acted == active_count;
    }

    // Advance to next round
    pub fn nextRound(self: *Self) void {
        if (self.round.next()) |next_round| {
            self.round = next_round;

            // Reset betting for new round
            for (self.players[0..self.num_players]) |*player| {
                player.bet_this_round = 0;
            }

            self.current_bet = 0;
            self.last_raiser = null;
            self.current_player = self.nextActivePlayer(self.dealer_button);
        }
    }

    // Check if game is terminal (showdown or all folded)
    pub fn isTerminal(self: Self) bool {
        // Game ends if only one player remains
        if (self.active_players <= 1) return true;
        
        // Game ends after river betting is complete
        if (self.round == .river and self.isBettingComplete()) return true;
        
        // Also check if all players are all-in
        var can_act_count: u8 = 0;
        for (self.players[0..self.num_players]) |player| {
            if (player.canAct()) {
                can_act_count += 1;
            }
        }
        
        // If no one can act, game is terminal
        return can_act_count == 0;
    }

    // Get information set string for current player
    pub fn getInfoSet(self: Self, player_id: u8) ![]u8 {
        var info_set = std.ArrayList(u8).init(self.allocator);
        defer info_set.deinit();

        const player = &self.players[player_id];

        // Add hole cards
        try info_set.append(player.hand.cards[0]);
        try info_set.append(player.hand.cards[1]);

        // Add board cards
        for (self.board[0..self.board_size]) |card| {
            try info_set.append(card);
        }

        // Add action sequence
        for (self.action_sequence.items) |action| {
            try info_set.append(action);
        }

        return info_set.toOwnedSlice();
    }

    // Helper functions
    fn advanceToNextPlayer(self: *Self) void {
        self.current_player = self.nextActivePlayer(self.current_player);
    }

    fn nextActivePlayer(self: Self, start: u8) u8 {
        var next = (start + 1) % self.num_players;
        while (next != start and !self.players[next].canAct()) {
            next = (next + 1) % self.num_players;
        }
        return next;
    }
    
    // Get legal actions for current player
    pub fn getLegalActions(self: *Self) []const Action {
        const player = &self.players[self.current_player];
        
        // Reset action buffer
        self.legal_actions_count = 0;
        
        // Can always fold if there's a bet to call
        if (self.current_bet > player.bet_this_round) {
            self.legal_actions_buffer[self.legal_actions_count] = Action.fold();
            self.legal_actions_count += 1;
            
            // Can call if we have chips
            if (player.stack > 0) {
                self.legal_actions_buffer[self.legal_actions_count] = Action.call();
                self.legal_actions_count += 1;
            }
        } else {
            // Can check if no bet to call
            self.legal_actions_buffer[self.legal_actions_count] = Action.check();
            self.legal_actions_count += 1;
        }
        
        // Can raise if we have enough chips
        const min_raise = self.big_blind;
        if (player.stack > (self.current_bet - player.bet_this_round + min_raise)) {
            self.legal_actions_buffer[self.legal_actions_count] = Action.raise(self.current_bet + min_raise);
            self.legal_actions_count += 1;
        }
        
        // Can go all-in if we have chips
        if (player.stack > 0 and player.stack <= (self.current_bet - player.bet_this_round + min_raise)) {
            self.legal_actions_buffer[self.legal_actions_count] = Action.allIn(player.stack);
            self.legal_actions_count += 1;
        }
        
        return self.legal_actions_buffer[0..self.legal_actions_count];
    }
    
    // Get information set key (hash) for MCCFR
    pub fn getInfoSetKey(self: *const Self, player_id: u8) !u64 {
        var hasher = std.hash.Wyhash.init(0);
        const player = &self.players[player_id];
        
        // Hash hole cards
        hasher.update(std.mem.asBytes(&player.hand.cards));
        
        // Hash board cards
        hasher.update(self.board[0..self.board_size]);
        
        // Hash action sequence
        hasher.update(self.action_sequence.items);
        
        return hasher.final();
    }
    
    // Clone the game state for tree traversal
    pub fn clone(self: *const Self) !Self {
        // Prevent excessive cloning that causes memory exhaustion
        // Increased limit to handle exploitability calculation which explores deeper
        if (self.actions.items.len > 500) { // Higher limit for exploitability calculation
            std.log.err("Action history too long for cloning: {d} actions", .{self.actions.items.len});
            return error.ActionHistoryTooLong;
        }
        
        const new_state = Self{
            .players = self.players,
            .num_players = self.num_players,
            .active_players = self.active_players,
            .round = self.round,
            .board = self.board,
            .board_size = self.board_size,
            .deck_position = self.deck_position,
            .deck = self.deck,
            .current_player = self.current_player,
            .dealer_button = self.dealer_button,
            .small_blind = self.small_blind,
            .big_blind = self.big_blind,
            .pot = self.pot,
            .current_bet = self.current_bet,
            .last_raiser = self.last_raiser,
            .actions = try self.actions.clone(),
            .action_sequence = try self.action_sequence.clone(),
            .allocator = self.allocator,
            .legal_actions_buffer = self.legal_actions_buffer,
            .legal_actions_count = self.legal_actions_count,
        };
        return new_state;
    }
    
    // Get utility for a player (payoff at terminal node)
    pub fn getUtility(self: *const Self, player_id: u8) f32 {
        if (!self.isTerminal()) return 0.0;
        
        // Simplified utility calculation
        // In a real implementation, this would calculate winnings based on hand strength
        if (!self.players[player_id].is_active) {
            return -@as(f32, @floatFromInt(self.players[player_id].total_bet));
        }
        
        // If only one player left, they win the pot
        if (self.active_players == 1) {
            if (self.players[player_id].is_active) {
                return @as(f32, @floatFromInt(self.pot - self.players[player_id].total_bet));
            }
        }
        
        // Placeholder for showdown logic
        // Would need hand evaluation here
        return 0.0;
    }
    
    // Shuffle deck for new game
    pub fn shuffleDeck(self: *Self, rng: std.Random) void {
        // Fisher-Yates shuffle
        var i: usize = 52;
        while (i > 1) {
            i -= 1;
            const j = rng.uintLessThan(usize, i + 1);
            const temp = self.deck[i];
            self.deck[i] = self.deck[j];
            self.deck[j] = temp;
        }
        self.deck_position = 0;
    }
    
    // Deal next card from deck
    pub fn dealCard(self: *Self) Card {
        const card = self.deck[self.deck_position];
        self.deck_position += 1;
        return card;
    }
};

test "player initialization" {
    const testing = std.testing;

    var player = Player.init(0, 1000);
    try testing.expect(player.stack == 1000);
    try testing.expect(player.is_active);
    try testing.expect(!player.is_all_in);
    try testing.expect(player.hand.isEmpty());
}

test "action creation" {
    const testing = std.testing;

    const fold_action = Action.fold();
    try testing.expectEqual(ActionType.fold, fold_action.action_type);
    try testing.expectEqual(@as(u32, 0), fold_action.amount);

    const raise_action = Action.raise(100);
    try testing.expectEqual(ActionType.raise, raise_action.action_type);
    try testing.expectEqual(@as(u32, 100), raise_action.amount);
    try testing.expect(raise_action.isAgressive());
}

test "game state initialization" {
    const testing = std.testing;

    var state = try GameState.init(testing.allocator, 2, 5, 10);
    defer state.deinit();

    try testing.expectEqual(@as(u8, 2), state.num_players);
    try testing.expectEqual(Round.preflop, state.round);
    try testing.expectEqual(@as(u32, 5), state.small_blind);
    try testing.expectEqual(@as(u32, 10), state.big_blind);
    try testing.expectEqual(@as(u32, 0), state.pot); // Pot should start at 0
}

test "pot calculation with blinds and actions" {
    const testing = std.testing;

    var state = try GameState.init(testing.allocator, 2, 5, 10);
    defer state.deinit();

    // Post blinds
    try state.postBlinds();
    try testing.expectEqual(@as(u32, 15), state.pot); // SB + BB = 5 + 10 = 15
    try testing.expectEqual(@as(u32, 10), state.current_bet); // BB sets current bet

    // Player calls
    const call_action = Action.call();
    const success = try state.applyAction(call_action);
    try testing.expect(success);
    try testing.expectEqual(@as(u32, 20), state.pot); // 15 + 5 (call amount) = 20
}

test "pot calculation with raises" {
    const testing = std.testing;

    var state = try GameState.init(testing.allocator, 2, 5, 10);
    defer state.deinit();

    // Post blinds
    try state.postBlinds();
    try testing.expectEqual(@as(u32, 15), state.pot); // SB + BB = 5 + 10 = 15
    try testing.expectEqual(@as(u32, 10), state.current_bet); // BB sets current bet

    // Player raises to 20
    const raise_action = Action.raise(10); // Raise by 10 (total bet becomes 20)
    const success = try state.applyAction(raise_action);
    try testing.expect(success);
    try testing.expectEqual(@as(u32, 30), state.pot); // 15 + 15 (raise amount) = 30
    try testing.expectEqual(@as(u32, 20), state.current_bet); // New current bet is 20
}
