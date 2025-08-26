//! Tests for 8-player game support
//! Verifies all components work with MAX_PLAYERS = 8

const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");
const config = poker_ai.config;
const game_engine = poker_ai.game_engine;
const pot = poker_ai.pot;
const betting = poker_ai.betting;

test "verify MAX_PLAYERS is 8" {
    try testing.expectEqual(@as(u8, 8), config.MAX_PLAYERS);
    try testing.expectEqual(@as(u8, 8), game_engine.MAX_PLAYERS);
    try testing.expectEqual(@as(u8, 8), pot.MAX_PLAYERS);
    try testing.expectEqual(@as(u8, 8), betting.MAX_PLAYERS);
}

test "8 player game initialization" {
    const GameConfig = game_engine.GameConfig;
    const TexasHoldemGameEngine = game_engine.TexasHoldemGameEngine;
    
    const game_config = GameConfig{
        .small_blind = 10,
        .big_blind = 20,
        .initial_stack = 1500,
    };
    
    var engine = try TexasHoldemGameEngine.init(testing.allocator, 8, game_config);
    defer engine.deinit();
    
    try testing.expectEqual(@as(u8, 8), engine.num_players);
    try testing.expectEqual(@as(u8, 8), engine.active_players);
    
    // Verify all players are initialized
    for (0..8) |i| {
        const p = engine.players[i];
        try testing.expectEqual(@as(u8, @intCast(i)), p.id);
        try testing.expectEqual(@as(u32, 1500), p.stack);
        try testing.expect(p.is_active);
    }
}

test "8 player pot calculation" {
    const PotManager = pot.PotManager;
    var pot_manager = PotManager.init(testing.allocator);
    defer pot_manager.deinit();
    
    // Simulate contributions from 8 players
    for (0..8) |player_id| {
        try pot_manager.addToPot(@intCast(player_id), 100);
    }
    
    try testing.expectEqual(@as(u32, 800), pot_manager.getTotalPot());
}

test "8 player betting round" {
    const BettingManager = betting.BettingManager;
    var betting_manager = BettingManager.init();
    
    // Initialize with 8 players
    betting_manager.startNewRound(8);
    
    // Simulate actions from all 8 players
    for (0..8) |player_id| {
        const action = betting.Action{
            .player_id = @intCast(player_id),
            .action_type = .call,
            .amount = 20,
        };
        betting_manager.recordAction(action);
    }
    
    // Verify betting round tracks all 8 players
    var acted_count: u8 = 0;
    for (0..8) |i| {
        if (betting_manager.players_who_acted[i]) {
            acted_count += 1;
        }
    }
    try testing.expectEqual(@as(u8, 8), acted_count);
}

test "8 player showdown evaluation" {
    const GameConfig = game_engine.GameConfig;
    const TexasHoldemGameEngine = game_engine.TexasHoldemGameEngine;
    
    const game_config = GameConfig{
        .small_blind = 10,
        .big_blind = 20,
        .initial_stack = 1500,
    };
    
    var engine = try TexasHoldemGameEngine.init(testing.allocator, 8, game_config);
    defer engine.deinit();
    
    // Deal cards to 8 players
    const hole_cards = [_][2]u8{
        .{ 0, 1 },   // Player 0: Ace-2 of spades
        .{ 2, 3 },   // Player 1: 3-4 of spades
        .{ 4, 5 },   // Player 2: 5-6 of spades
        .{ 6, 7 },   // Player 3: 7-8 of spades
        .{ 8, 9 },   // Player 4: 9-10 of spades
        .{ 10, 11 }, // Player 5: J-Q of spades
        .{ 12, 13 }, // Player 6: K-A of hearts
        .{ 14, 15 }, // Player 7: 2-3 of hearts
    };
    
    for (0..8) |i| {
        engine.players[i].hole_cards = hole_cards[i];
        engine.players[i].has_cards = true;
    }
    
    // Set board cards
    engine.board = [_]u8{ 16, 17, 18, 19, 20 }; // Some community cards
    engine.board_size = 5;
    
    // Move to showdown
    engine.betting_stage = .show_down;
    
    // Get payouts for all 8 players
    const payouts = try engine.getPayouts();
    
    // Verify we get payouts for exactly 8 players
    var payout_count: u8 = 0;
    for (payouts) |payout| {
        _ = payout;
        payout_count += 1;
    }
    try testing.expectEqual(@as(u8, 8), payout_count);
}

test "8 player memory allocation" {
    const GameState = poker_ai.game_state.GameState;
    
    var state = try GameState.init(testing.allocator, 8, 10, 20);
    defer state.deinit();
    
    try testing.expectEqual(@as(u8, 8), state.num_players);
    
    // Verify all 8 player slots are available
    for (0..8) |i| {
        _ = state.players[i];
    }
}

test "8 player game tree node" {
    const GameNode = poker_ai.game_tree.GameNode;
    
    const node = GameNode{
        .state_hash = 12345,
        .player = 0,
        .round = .flop,
        .pot = 100,
        .active_players = 8,
        .first_child_idx = 0,
        .num_children = 3,
        .is_terminal = false,
        .depth = 1,
        .utilities = null,
    };
    
    try testing.expectEqual(@as(u8, 8), node.active_players);
    
    // Test with utilities
    var utils: [config.MAX_PLAYERS]f32 = undefined;
    for (0..8) |i| {
        utils[i] = @floatFromInt(i * 10);
    }
    
    const terminal_node = GameNode{
        .state_hash = 54321,
        .player = 0,
        .round = .river,
        .pot = 500,
        .active_players = 8,
        .first_child_idx = 0,
        .num_children = 0,
        .is_terminal = true,
        .depth = 10,
        .utilities = utils,
    };
    
    try testing.expect(terminal_node.utilities != null);
    if (terminal_node.utilities) |u| {
        for (0..8) |i| {
            try testing.expectEqual(@as(f32, @floatFromInt(i * 10)), u[i]);
        }
    }
}

test "8 player display layout" {
    const TableLayout = poker_ai.game_display.TableLayout;
    
    const layout = TableLayout.init(140, 40); // Wider terminal for 8 players
    
    // Verify all 8 player positions are within bounds
    for (0..8) |i| {
        const pos = layout.getPlayerPosition(@intCast(i), 8);
        try testing.expect(pos.x > 0 and pos.x < 140);
        try testing.expect(pos.y > 0 and pos.y < 40);
        
        // Verify positions are reasonably spaced
        if (i > 0) {
            const prev_pos = layout.getPlayerPosition(@intCast(i - 1), 8);
            const dist_sq = (pos.x - prev_pos.x) * (pos.x - prev_pos.x) + 
                           (pos.y - prev_pos.y) * (pos.y - prev_pos.y);
            try testing.expect(dist_sq > 100); // Minimum distance between players
        }
    }
}

test "8 player MCCFR config" {
    const mccfr_config = config.getMCCFRConfig(8);
    
    // Verify appropriate settings for 8 players
    try testing.expectEqual(@as(u32, 200000), mccfr_config.iterations);
    try testing.expectEqual(@as(u32, 250), mccfr_config.batch_size);
    try testing.expectEqual(@as(f32, 0.5), mccfr_config.exploration_epsilon);
    try testing.expectEqual(@as(f32, -500.0), mccfr_config.pruning_threshold);
}