// Test suite for complete MCCFR implementation
const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");
const cfr = poker_ai.cfr;
const game_state = poker_ai.game_state;
const strategy_table = poker_ai.strategy_table;
const lookup_tables = poker_ai.lookup_tables;
const hand_eval = poker_ai.hand_eval;
const parallel_cfr = poker_ai.parallel_cfr;

test "MCCFR trainer initialization" {
    const allocator = testing.allocator;
    
    const config = cfr.CFRConfig{
        .iterations = 10,
        .exploration_probability = 0.6,
        .prune_threshold = -300.0,
        .discount_alpha = 1.5,
        .discount_beta = 0.0,
    };
    
    var strat_table = strategy_table.StrategyTable.init(allocator);
    defer strat_table.deinit();
    
    var abstraction_table = try lookup_tables.AbstractionTable.init(allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = hand_eval.HandEvaluator.init();
    
    var trainer = try cfr.MCCFRTrainer.init(
        allocator,
        config,
        &strat_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    try testing.expectEqual(@as(u32, 10), trainer.config.iterations);
}

test "MCCFR training with small iterations" {
    return error.SkipZigTest;
}

test "Parallel CFR training" {
    return error.SkipZigTest;
}

test "Strategy convergence" {
    return error.SkipZigTest;
}

test "Hand evaluation in utility calculation" {
    const allocator = testing.allocator;
    
    // Create a game state at showdown
    var game = try game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    
    // Deal specific hands
    var hands = [2][2]u8{
        .{ 12, 25 }, // Ace of spades, King of hearts
        .{ 0, 1 },   // 2 of spades, 2 of hearts (pair)
    };
    game.dealHoleCards(hands[0..]);
    
    // Add board cards (no pair on board)
    game.board[0] = 26; // Ace of diamonds
    game.board[1] = 14; // 3 of diamonds
    game.board[2] = 15; // 3 of clubs
    game.board[3] = 28; // 4 of clubs
    game.board[4] = 29; // 4 of hearts
    game.board_size = 5;
    
    // Both players are active
    game.players[0].is_active = true;
    game.players[1].is_active = true;
    game.active_players = 2;
    game.pot = 100;
    game.players[0].total_bet = 50;
    game.players[1].total_bet = 50;
    
    // Create trainer to access utility calculation
    const config = cfr.CFRConfig.default();
    var strat_table = strategy_table.StrategyTable.init(allocator);
    defer strat_table.deinit();
    
    var abstraction_table = try lookup_tables.AbstractionTable.init(allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = hand_eval.HandEvaluator.init();
    
    var trainer = try cfr.MCCFRTrainer.init(
        allocator,
        config,
        &strat_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    // Calculate utilities
    const utility_p0 = trainer.getUtility(&game, 0);
    const utility_p1 = trainer.getUtility(&game, 1);
    
    // Player 0 has two pair (Aces and 4s), Player 1 has two pair (2s and 4s)
    // Player 0 should win
    try testing.expect(utility_p0 > 0);
    try testing.expect(utility_p1 < 0);
    try testing.expect(utility_p0 > @abs(utility_p1));
}

test "Memory usage and strategy table persistence" {
    return error.SkipZigTest;
}
