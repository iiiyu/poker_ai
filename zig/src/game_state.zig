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
        };
        
        // Initialize players
        for (state.players[0..num_players], 0..) |*player, i| {
            player.* = Player.init(@intCast(i), 1000); // Default stack
        }
        
        return state;
    }
    
    pub fn deinit(self: *Self) void {
        self.actions.deinit();
        self.action_sequence.deinit();
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
        const new_cards = switch (self.round) {
            .preflop => 0,
            .flop => 3,
            .turn => 1,
            .river => 1,
        };
        
        for (cards[0..new_cards], 0..) |card, i| {
            self.board[board_start + i] = card;
        }
        
        self.board_size = self.round.boardSize() + @as(u8, @intCast(new_cards));
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
        return self.active_players <= 1 or self.round == .river and self.isBettingComplete();
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
}