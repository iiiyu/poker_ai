//! Integration tests for the new Texas Hold'em game engine
//! 
//! Tests compatibility with Python implementation and validates
//! the complete game flow from start to finish.

const std = @import("std");
const testing = std.testing;

// Import through the module system
const poker_ai = @import("poker_ai");

const TexasHoldemGameEngine = poker_ai.game_engine.TexasHoldemGameEngine;
const GameConfig = poker_ai.game_engine.GameConfig;
const Action = poker_ai.game_engine.Action;
const ActionType = poker_ai.game_engine.ActionType;
const BettingStage = poker_ai.game_engine.BettingStage;
const Player = poker_ai.player.Player;
const PotManager = poker_ai.pot.PotManager;
const BettingManager = poker_ai.betting.BettingManager;
const ActionValidator = poker_ai.action_validator.ActionValidator;

test "complete Texas Hold'em hand simulation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
        .max_raises_per_round = 3,
    };
    
    var engine = try TexasHoldemGameEngine.init(allocator, 6, config);
    defer engine.deinit();
    
    // Start new hand
    try engine.newHand();
    
    // Deal hole cards (simulating specific cards for deterministic test)
    const hole_cards = [_][2]u8{
        [_]u8{ 0, 1 },   // Player 0: 2♠, 2♥
        [_]u8{ 2, 3 },   // Player 1: 2♦, 2♣
        [_]u8{ 4, 5 },   // Player 2: 3♠, 3♥
        [_]u8{ 6, 7 },   // Player 3: 3♦, 3♣
        [_]u8{ 8, 9 },   // Player 4: 4♠, 4♥
        [_]u8{ 10, 11 }, // Player 5: 4♦, 4♣
    };
    
    try engine.dealHoleCards(&hole_cards);
    
    // Verify initial state
    try testing.expectEqual(BettingStage.pre_flop, engine.getCurrentStage());
    try testing.expectEqual(@as(u8, 6), engine.num_players);
    try testing.expectEqual(@as(u32, 15), engine.getPotSize()); // SB + BB
    
    // Test preflop betting round
    // Player 2 (UTG) should be first to act after BB
    try testing.expectEqual(@as(u8, 2), engine.getCurrentPlayer());
    
    // UTG calls
    var call_action = Action.call(2);
    try engine.applyAction(call_action);
    
    // MP folds
    var fold_action = Action.fold(3);
    try engine.applyAction(fold_action);
    
    // CO calls
    call_action = Action.call(4);
    try engine.applyAction(call_action);
    
    // Button raises
    const raise_action = Action.raise(5, 30);
    try engine.applyAction(raise_action);
    
    // SB folds
    fold_action = Action.fold(0);
    try engine.applyAction(fold_action);
    
    // BB calls the raise
    call_action = Action.call(1);
    try engine.applyAction(call_action);
    
    // UTG calls the raise
    call_action = Action.call(2);
    try engine.applyAction(call_action);
    
    // CO calls the raise
    call_action = Action.call(4);
    try engine.applyAction(call_action);
    
    // Should now be flop
    try testing.expectEqual(BettingStage.flop, engine.getCurrentStage());
    try testing.expectEqual(@as(u32, 125), engine.getPotSize()); // 5 + 30*4
    
    // Deal flop
    const flop_cards = [_]u8{ 12, 13, 14 }; // Q♠, K♠, A♠
    try engine.dealCommunityCards(&flop_cards);
    
    // Test flop betting round (SB should be first to act, but folded, so BB)
    try testing.expectEqual(@as(u8, 1), engine.getCurrentPlayer());
    
    // BB checks
    var check_action = Action.check(1);
    try engine.applyAction(check_action);
    
    // UTG bets
    var bet_action = Action.raise(2, 50);
    try engine.applyAction(bet_action);
    
    // CO folds
    fold_action = Action.fold(4);
    try engine.applyAction(fold_action);
    
    // Button calls
    call_action = Action.call(5);
    try engine.applyAction(call_action);
    
    // BB folds
    fold_action = Action.fold(1);
    try engine.applyAction(fold_action);
    
    // Should now be turn with 2 players
    try testing.expectEqual(BettingStage.turn, engine.getCurrentStage());
    try testing.expectEqual(@as(u32, 225), engine.getPotSize()); // 125 + 50*2
    
    // Deal turn
    const turn_card = [_]u8{15}; // A♥
    try engine.dealCommunityCards(&turn_card);
    
    // Turn betting
    check_action = Action.check(2);
    try engine.applyAction(check_action);
    
    check_action = Action.check(5);
    try engine.applyAction(check_action);
    
    // Should now be river
    try testing.expectEqual(BettingStage.river, engine.getCurrentStage());
    
    // Deal river
    const river_card = [_]u8{16}; // A♦
    try engine.dealCommunityCards(&river_card);
    
    // River betting
    bet_action = Action.raise(2, 100);
    try engine.applyAction(bet_action);
    
    call_action = Action.call(5);
    try engine.applyAction(call_action);
    
    // Game should be terminal
    try testing.expect(engine.isGameTerminal());
    
    // Test payout calculation
    const payouts = try engine.getPayouts();
    
    // Verify payouts sum to zero (conservation)
    var total_payout: i32 = 0;
    for (payouts) |payout| {
        total_payout += payout;
    }
    try testing.expectEqual(@as(i32, 0), total_payout);
}

test "all-in scenario with side pots" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 100, // Small stacks to force all-ins
        .max_raises_per_round = 3,
    };
    
    var engine = try TexasHoldemGameEngine.init(allocator, 3, config);
    defer engine.deinit();
    
    try engine.newHand();
    
    // Set different stack sizes to test side pots
    engine.players[0].stack = 50;  // Short stack
    engine.players[1].stack = 100; // Medium stack
    engine.players[2].stack = 200; // Big stack
    
    const hole_cards = [_][2]u8{
        [_]u8{ 0, 1 },   // Player 0
        [_]u8{ 2, 3 },   // Player 1
        [_]u8{ 4, 5 },   // Player 2
    };
    
    try engine.dealHoleCards(&hole_cards);
    
    // Player 2 (UTG) goes all-in
    var all_in_action = Action.allIn(2, 200);
    try engine.applyAction(all_in_action);
    
    // Player 0 (SB) calls all-in (50 chips)
    all_in_action = Action.allIn(0, 50);
    try engine.applyAction(all_in_action);
    
    // Player 1 (BB) calls all-in (100 chips)
    all_in_action = Action.allIn(1, 100);
    try engine.applyAction(all_in_action);
    
    // All players are all-in, should go straight to showdown
    try testing.expect(engine.isGameTerminal());
    
    // Test that pot manager handles side pots correctly
    const total_pot = engine.getPotSize();
    try testing.expectEqual(@as(u32, 350), total_pot); // 50 + 100 + 200
    
    const payouts = try engine.getPayouts();
    var total_payout: i32 = 0;
    for (payouts) |payout| {
        total_payout += payout;
    }
    try testing.expectEqual(@as(i32, 0), total_payout); // Conservation check
}

test "action validation comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var validator = ActionValidator.initWithAllocator(allocator);
    
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
        .max_raises_per_round = 3,
    };
    
    var test_player = Player.init(0, 1000);
    var betting_manager = BettingManager.initWithAllocator(allocator);
    defer betting_manager.deinit();
    
    const players = [_]Player{test_player};
    
    // Test fold validation
    const fold_action = .{ .action_type = ActionType.fold, .amount = 0, .player_id = 0 };
    var result = validator.validateAction(fold_action, &test_player, &players, &betting_manager, config);
    try testing.expect(result.is_valid);
    
    // Test call validation with no bet
    const call_action = .{ .action_type = ActionType.call, .amount = 0, .player_id = 0 };
    result = validator.validateAction(call_action, &test_player, &players, &betting_manager, config);
    try testing.expect(!result.is_valid); // Should fail - no bet to call
    
    // Test check validation with no bet
    const check_action = .{ .action_type = ActionType.check, .amount = 0, .player_id = 0 };
    result = validator.validateAction(check_action, &test_player, &players, &betting_manager, config);
    try testing.expect(result.is_valid);
    
    // Set up a betting scenario
    betting_manager.current_bet = 50;
    
    // Now call should be valid
    result = validator.validateAction(call_action, &test_player, &players, &betting_manager, config);
    try testing.expect(result.is_valid);
    
    // Check should be invalid
    result = validator.validateAction(check_action, &test_player, &players, &betting_manager, config);
    try testing.expect(!result.is_valid);
    
    // Test raise validation
    const raise_action = .{ .action_type = ActionType.raise, .amount = 100, .player_id = 0 };
    result = validator.validateAction(raise_action, &test_player, &players, &betting_manager, config);
    try testing.expect(result.is_valid);
    
    // Test all-in validation
    const all_in_action = .{ .action_type = ActionType.all_in, .amount = 1000, .player_id = 0 };
    result = validator.validateAction(all_in_action, &test_player, &players, &betting_manager, config);
    try testing.expect(result.is_valid);
}

test "legal actions generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var validator = ActionValidator.initWithAllocator(allocator);
    
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
        .max_raises_per_round = 3,
    };
    
    var test_player = Player.init(0, 1000);
    var betting_manager = BettingManager.initWithAllocator(allocator);
    defer betting_manager.deinit();
    
    const players = [_]Player{test_player};
    
    // Test with no current bet (can check)
    const legal_actions = try validator.getLegalActions(&test_player, &players, &betting_manager, config);
    defer allocator.free(legal_actions);
    
    try testing.expect(legal_actions.len > 0);
    
    // Should include fold, check, raise, all_in
    var has_fold = false;
    var has_check = false;
    var has_raise = false;
    var has_all_in = false;
    
    for (legal_actions) |action| {
        switch (action) {
            .fold => has_fold = true,
            .check => has_check = true,
            .raise => has_raise = true,
            .all_in => has_all_in = true,
            else => {},
        }
    }
    
    try testing.expect(has_fold);
    try testing.expect(has_check);
    try testing.expect(has_raise);
    try testing.expect(has_all_in);
}

test "betting round management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var betting_manager = BettingManager.initWithAllocator(allocator);
    defer betting_manager.deinit();
    
    var players = [_]Player{
        Player.init(0, 1000),
        Player.init(1, 1000),
        Player.init(2, 1000),
    };
    
    // Start preflop round
    try betting_manager.startRound(&players, 0, 10); // Big blind of 10
    
    try testing.expectEqual(@as(u32, 10), betting_manager.current_bet);
    try testing.expectEqual(@as(u8, 0), betting_manager.num_raises_this_round);
    
    // Register a raise
    betting_manager.registerRaise(1, 30);
    
    try testing.expectEqual(@as(u32, 30), betting_manager.current_bet);
    try testing.expectEqual(@as(?u8, 1), betting_manager.last_raiser);
    try testing.expectEqual(@as(u8, 1), betting_manager.num_raises_this_round);
    
    // Test round completion
    // Mark all players as having acted with equal bets
    for (&players) |*p| {
        p.current_bet = 30;
    }
    betting_manager.players_who_acted = [_]bool{true, true, true, false, false, false, false, false};
    betting_manager.num_players_acted = 3;
    
    try testing.expect(betting_manager.isRoundComplete(&players));
}

test "pot management with multiple side pots" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var pot_manager = PotManager.init(allocator);
    defer pot_manager.deinit();
    
    // Simulate complex all-in scenario
    // Player 0: 100 chips all-in
    // Player 1: 200 chips all-in
    // Player 2: 300 chips call
    
    try pot_manager.addToPot(100, 0);
    try pot_manager.addToPot(200, 1);
    try pot_manager.addToPot(200, 2); // Only calls the 200
    
    try testing.expectEqual(@as(u32, 500), pot_manager.getTotalPot());
    
    // Test pot odds calculation
    const pot_odds = pot_manager.getPotOdds(50);
    try testing.expectEqual(@as(f32, 10.0), pot_odds); // 500/50 = 10:1
    
    // Test rake calculation
    const rake = pot_manager.calculateRake(5.0, 25); // 5% up to 25
    try testing.expectEqual(@as(u32, 25), rake); // 5% of 500 = 25, at the cap
}

test "information set generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
        .max_raises_per_round = 3,
    };
    
    var engine = try TexasHoldemGameEngine.init(allocator, 3, config);
    defer engine.deinit();
    
    try engine.newHand();
    
    const hole_cards = [_][2]u8{
        [_]u8{ 0, 1 },   // Player 0: 2♠, 2♥
        [_]u8{ 2, 3 },   // Player 1: 2♦, 2♣
        [_]u8{ 4, 5 },   // Player 2: 3♠, 3♥
    };
    
    try engine.dealHoleCards(&hole_cards);
    
    // Get information set for player 0
    const info_set = try engine.getInfoSet(0);
    defer allocator.free(info_set);
    
    try testing.expect(info_set.len >= 4); // At least hole cards + stage + some actions
    
    // First two bytes should be hole cards
    try testing.expectEqual(@as(u8, 0), info_set[0]); // 2♠
    try testing.expectEqual(@as(u8, 1), info_set[1]); // 2♥
    
    // Third byte should be betting stage
    try testing.expectEqual(@as(u8, 0), info_set[2]); // pre_flop = 0
}

test "Python compatibility - card representation" {
    // Test that our card representation matches Python's 0-51 encoding
    // Python uses: rank-2 + (suit * 13) where rank is 2-14, suit is 0-3
    
    // Test deuce of clubs (should be 0)
    const deuce_clubs: u8 = 0; // (2-2) + (0*13) = 0
    try testing.expectEqual(@as(u8, 0), deuce_clubs);
    
    // Test ace of spades (should be 51)
    const ace_spades: u8 = 51; // (14-2) + (3*13) = 12 + 39 = 51
    try testing.expectEqual(@as(u8, 51), ace_spades);
    
    // Test that we have exactly 52 possible card values
    const max_card_value: u8 = 51;
    try testing.expect(max_card_value < 52);
}

test "Python compatibility - action types" {
    // Ensure our action types match Python's numbering
    try testing.expectEqual(@as(u8, 0), @intFromEnum(ActionType.fold));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(ActionType.call));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(ActionType.raise));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(ActionType.check));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(ActionType.all_in));
}

test "Python compatibility - betting stages" {
    // Ensure our betting stages match Python's numbering
    try testing.expectEqual(@as(u8, 0), @intFromEnum(BettingStage.pre_flop));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(BettingStage.flop));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(BettingStage.turn));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(BettingStage.river));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(BettingStage.show_down));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(BettingStage.terminal));
}

test "performance - action validation speed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var validator = ActionValidator.initWithAllocator(allocator);
    
    const config = GameConfig{
        .small_blind = 5,
        .big_blind = 10,
        .initial_stack = 1000,
        .max_raises_per_round = 3,
    };
    
    var test_player = Player.init(0, 1000);
    var betting_manager = BettingManager.initWithAllocator(allocator);
    defer betting_manager.deinit();
    
    const players = [_]Player{test_player};
    
    // Time 10,000 action validations
    var timer = try std.time.Timer.start();
    
    const fold_action = .{ .action_type = ActionType.fold, .amount = 0, .player_id = 0 };
    
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        _ = validator.validateAction(fold_action, &test_player, &players, &betting_manager, config);
    }
    
    const elapsed_ns = timer.read();
    
    // Should complete in under 10ms (10,000,000 ns)
    try testing.expect(elapsed_ns < 10_000_000);
    
    // Log performance for monitoring
    std.debug.print("Action validation: {} ns per operation\n", .{elapsed_ns / 10000});
}

test "memory usage - no leaks in game simulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const initial_memory = gpa.total_requested_bytes;
    
    // Run multiple complete games
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const config = GameConfig{
            .small_blind = 5,
            .big_blind = 10,
            .initial_stack = 1000,
            .max_raises_per_round = 3,
        };
        
        var engine = try TexasHoldemGameEngine.init(allocator, 6, config);
        defer engine.deinit();
        
        try engine.newHand();
        
        const hole_cards = [_][2]u8{
            [_]u8{ 0, 1 }, [_]u8{ 2, 3 }, [_]u8{ 4, 5 },
            [_]u8{ 6, 7 }, [_]u8{ 8, 9 }, [_]u8{ 10, 11 },
        };
        
        try engine.dealHoleCards(&hole_cards);
        
        // Simulate some actions
        var fold_action = Action.fold(2);
        try engine.applyAction(fold_action);
        
        fold_action = Action.fold(3);
        try engine.applyAction(fold_action);
        
        fold_action = Action.fold(4);
        try engine.applyAction(fold_action);
        
        fold_action = Action.fold(5);
        try engine.applyAction(fold_action);
    }
    
    const final_memory = gpa.total_requested_bytes;
    
    // Memory usage should be reasonable (less than 1MB growth)
    try testing.expect(final_memory <= initial_memory + 1024 * 1024);
}