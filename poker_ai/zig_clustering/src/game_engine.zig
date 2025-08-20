const std = @import("std");
const Card = @import("eval_card.zig").Card;
const EvalCard = @import("eval_card.zig").EvalCard;

// Texas Hold'em Game Engine Components

// Deck management
pub const Deck = struct {
    cards: [52]Card,
    top: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !Deck {
        const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
        defer allocator.free(all_cards);
        
        var deck = Deck{
            .cards = undefined,
            .top = 0,
            .allocator = allocator,
        };
        
        for (all_cards, 0..) |card, i| {
            deck.cards[i] = card;
        }
        
        return deck;
    }
    
    pub fn shuffle(self: *Deck, seed: u64) void {
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();
        
        // Fisher-Yates shuffle
        var i = self.cards.len - 1;
        while (i > 0) : (i -= 1) {
            const j = random.intRangeLessThan(usize, 0, i + 1);
            const temp = self.cards[i];
            self.cards[i] = self.cards[j];
            self.cards[j] = temp;
        }
        
        self.top = 0;
    }
    
    pub fn deal(self: *Deck) ?Card {
        if (self.top >= self.cards.len) return null;
        const card = self.cards[self.top];
        self.top += 1;
        return card;
    }
    
    pub fn reset(self: *Deck) void {
        self.top = 0;
    }
};

// Player representation
pub const PlayerStatus = enum {
    Active,
    Folded,
    AllIn,
};

pub const Player = struct {
    id: u32,
    hole_cards: [2]Card,
    chips: i64,
    current_bet: i64,
    status: PlayerStatus,
    position: u8,
    
    pub fn init(id: u32, chips: i64, position: u8) Player {
        return Player{
            .id = id,
            .hole_cards = undefined,
            .chips = chips,
            .current_bet = 0,
            .status = .Active,
            .position = position,
        };
    }
};

// Game state management
pub const Street = enum {
    PreFlop,
    Flop,
    Turn,
    River,
    Showdown,
};

pub const GameState = struct {
    street: Street,
    pot: i64,
    current_bet: i64,
    min_raise: i64,
    action_to: u8, // Player position
    betting_complete: bool,
    
    pub fn init() GameState {
        return GameState{
            .street = .PreFlop,
            .pot = 0,
            .current_bet = 0,
            .min_raise = 0,
            .action_to = 0,
            .betting_complete = false,
        };
    }
};

// Table management
pub const Table = struct {
    players: [8]?Player,
    community_cards: struct {
        flop: [3]Card,
        turn: ?Card,
        river: ?Card,
    },
    dealer_position: u8,
    small_blind_pos: u8,
    big_blind_pos: u8,
    deck: Deck,
    state: GameState,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !Table {
        return Table{
            .players = [_]?Player{null} ** 8,
            .community_cards = .{
                .flop = undefined,
                .turn = null,
                .river = null,
            },
            .dealer_position = 0,
            .small_blind_pos = 1,
            .big_blind_pos = 2,
            .deck = try Deck.init(allocator),
            .state = GameState.init(),
            .allocator = allocator,
        };
    }
    
    pub fn addPlayer(self: *Table, player: Player) !void {
        if (player.position >= 8) return error.InvalidPosition;
        self.players[player.position] = player;
    }
    
    pub fn dealHoleCards(self: *Table) void {
        // Deal 2 cards to each active player
        for (self.players) |*maybe_player| {
            if (maybe_player.*) |*player| {
                if (player.status == .Active) {
                    player.hole_cards[0] = self.deck.deal().?;
                    player.hole_cards[1] = self.deck.deal().?;
                }
            }
        }
    }
    
    pub fn dealFlop(self: *Table) void {
        // Burn one card
        _ = self.deck.deal();
        
        // Deal 3 flop cards
        self.community_cards.flop[0] = self.deck.deal().?;
        self.community_cards.flop[1] = self.deck.deal().?;
        self.community_cards.flop[2] = self.deck.deal().?;
        
        self.state.street = .Flop;
    }
    
    pub fn dealTurn(self: *Table) void {
        // Burn one card
        _ = self.deck.deal();
        
        // Deal turn card
        self.community_cards.turn = self.deck.deal();
        self.state.street = .Turn;
    }
    
    pub fn dealRiver(self: *Table) void {
        // Burn one card
        _ = self.deck.deal();
        
        // Deal river card
        self.community_cards.river = self.deck.deal();
        self.state.street = .River;
    }
    
    pub fn getBoardCards(self: *Table) []Card {
        var board = std.ArrayList(Card).init(self.allocator);
        defer board.deinit();
        
        // Add flop
        if (self.state.street != .PreFlop) {
            for (self.community_cards.flop) |card| {
                board.append(card) catch {};
            }
        }
        
        // Add turn
        if (self.state.street == .Turn or self.state.street == .River or self.state.street == .Showdown) {
            if (self.community_cards.turn) |turn| {
                board.append(turn) catch {};
            }
        }
        
        // Add river
        if (self.state.street == .River or self.state.street == .Showdown) {
            if (self.community_cards.river) |river| {
                board.append(river) catch {};
            }
        }
        
        return board.toOwnedSlice() catch &[_]Card{};
    }
};

// Pot management
pub const PotManager = struct {
    main_pot: i64,
    side_pots: std.ArrayList(SidePot),
    allocator: std.mem.Allocator,
    
    pub const SidePot = struct {
        amount: i64,
        eligible_players: []u32,
    };
    
    pub fn init(allocator: std.mem.Allocator) PotManager {
        return PotManager{
            .main_pot = 0,
            .side_pots = std.ArrayList(SidePot).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PotManager) void {
        for (self.side_pots.items) |pot| {
            self.allocator.free(pot.eligible_players);
        }
        self.side_pots.deinit();
    }
    
    pub fn addBet(self: *PotManager, amount: i64) void {
        self.main_pot += amount;
    }
    
    pub fn calculateSidePots(self: *PotManager, players: []Player) !void {
        _ = self;
        _ = players;
        // Sort players by their total contribution
        // Create side pots for all-in players
        // This is simplified - full implementation would track contributions per player
    }
};