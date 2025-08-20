const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");

// Integration tests that test component interactions
const allocator = testing.allocator;

// Import all modules for integration testing
const Card = @import("../src/cards.zig").Card;
const HandEvaluator = @import("../src/evaluator.zig").HandEvaluator;
const EquityCalculator = @import("../src/equity_calculator.zig").EquityCalculator;
const GameEngine = @import("../src/game_engine.zig").GameEngine;
const CFRSolver = @import("../src/cfr_solver.zig").CFRSolver;
const Storage = @import("../src/storage.zig").Storage;
const LUTBuilder = @import("../src/lut_builder.zig").LUTBuilder;

test "end-to-end poker game simulation" {
    // Test a complete poker game from start to finish
    var game_engine = try GameEngine.init(allocator, 3);
    defer game_engine.deinit();
    
    // Deal cards
    try game_engine.dealHoleCards();
    var game_state = game_engine.getGameState();
    
    // Verify all players have hole cards
    for (game_state.players) |player| {
        try testing.expect(player.hole_cards.len == 2);
    }
    
    // Betting round 1 (preflop)
    try game_engine.playerAction(0, .{ .bet = 10 });
    try game_engine.playerAction(1, .{ .call = 10 });
    try game_engine.playerAction(2, .fold);
    
    game_state = game_engine.getGameState();
    try testing.expect(game_state.pot == 20);
    try testing.expect(game_state.players[2].is_folded);
    
    // Deal flop
    try game_engine.dealFlop();
    game_state = game_engine.getGameState();
    try testing.expect(game_state.community_cards.len == 3);
    try testing.expect(game_state.current_round == .flop);
    
    // Betting round 2 (flop)
    try game_engine.playerAction(0, .check);
    try game_engine.playerAction(1, .{ .bet = 20 });
    try game_engine.playerAction(0, .{ .call = 20 });
    
    game_state = game_engine.getGameState();
    try testing.expect(game_state.pot == 60);
    
    // Deal turn and river
    try game_engine.dealTurn();
    try game_engine.dealRiver();
    
    game_state = game_engine.getGameState();
    try testing.expect(game_state.community_cards.len == 5);
    try testing.expect(game_state.current_round == .river);
    
    // Final betting round
    try game_engine.playerAction(0, .check);
    try game_engine.playerAction(1, .check);
    
    // Determine winner
    const winners = try game_engine.determineWinners(allocator);
    defer allocator.free(winners);
    
    try testing.expect(winners.len > 0);
    try testing.expect(winners[0] < 2); // Winner should be player 0 or 1
}

test "equity calculation with hand evaluator integration" {
    // Test that equity calculation correctly uses hand evaluation
    var equity_calc = EquityCalculator.init(allocator);
    
    const all_cards = try @import("../src/eval_card.zig").generateAllCards(allocator);
    defer allocator.free(all_cards);
    
    // Test case: AA vs random on dry board
    const pocket_aces = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "hearts"),
    };
    
    const dry_board = [_]Card{
        Card.init(2, "spades"),
        Card.init(7, "hearts"),
        Card.init(12, "diamonds"),
    };
    
    // Calculate equity
    const equity = try equity_calc.calculateEHS(&pocket_aces, &dry_board, all_cards, 1000, 42);
    
    // AA should have very high equity on dry board
    try testing.expect(equity > 0.7);
    try testing.expect(equity <= 1.0);
    
    // Verify the calculation makes sense by testing vs known weak hand
    const weak_hand = [_]Card{
        Card.init(2, "clubs"),
        Card.init(3, "diamonds"),
    };
    
    const weak_equity = try equity_calc.calculateEHS(&weak_hand, &dry_board, all_cards, 1000, 42);
    
    // AA should have much better equity than 23o
    try testing.expect(equity > weak_equity + 0.3);
}

test "storage and LUT builder integration" {
    const test_db = "integration_test.db";
    defer std.fs.cwd().deleteFile(test_db) catch {};
    
    // Test LUT building with storage backend
    var storage = try Storage.init(allocator, test_db, 10);
    defer storage.deinit();
    
    var lut_builder = try LUTBuilder.init(allocator, &storage, 50, 50, 50, 169);
    defer lut_builder.deinit();
    
    // Set low limits for fast test
    lut_builder.max_river_combos = 100;
    lut_builder.max_turn_combos = 50;
    lut_builder.max_flop_combos = 25;
    
    // Build river LUT (simplest case)
    try lut_builder.buildRiverLUT();
    
    // Verify data was stored
    try testing.expect(lut_builder.river_lut.count() > 0);
    
    // Test that we can retrieve stored data
    const river_count = lut_builder.river_lut.count();
    
    // Build turn LUT (depends on river)
    try lut_builder.buildTurnLUT();
    
    // Should have turn data now
    try testing.expect(lut_builder.turn_lut.count() > 0);
    
    // River data should still be intact
    try testing.expect(lut_builder.river_lut.count() == river_count);
}

test "CFR solver with game tree integration" {
    // Test that CFR can solve a simple game
    var cfr_solver = try CFRSolver.init(allocator, 2);
    defer cfr_solver.deinit();
    
    var game_tree = try @import("../src/game_tree.zig").GameTree.init(allocator);
    defer game_tree.deinit();
    
    // Run several iterations
    const iterations = 50;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try cfr_solver.runIteration(&game_tree, i);
    }
    
    // Get final strategy
    const strategy = cfr_solver.getAverageStrategy();
    try testing.expect(strategy.info_sets.count() > 0);
    
    // Calculate exploitability
    const exploitability = try cfr_solver.calculateExploitability(&game_tree);
    try testing.expect(exploitability >= 0.0);
    try testing.expect(!std.math.isNan(exploitability));
    
    // After 50 iterations, exploitability should be reasonable
    try testing.expect(exploitability < 1.0);
}

test "complete hand abstraction pipeline" {
    // Test the complete hand abstraction process
    const test_db = "abstraction_test.db";
    defer std.fs.cwd().deleteFile(test_db) catch {};
    
    var storage = try Storage.init(allocator, test_db, 5);
    defer storage.deinit();
    
    var lut_builder = try LUTBuilder.init(allocator, &storage, 20, 30, 40, 169);
    defer lut_builder.deinit();
    
    // Set minimal limits for fast test
    lut_builder.max_river_combos = 50;
    lut_builder.max_turn_combos = 30;
    lut_builder.max_flop_combos = 20;
    
    // Build complete abstraction
    try lut_builder.buildRiverLUT();
    try lut_builder.buildTurnLUT();
    try lut_builder.buildFlopLUT();
    
    // Verify all stages have data
    try testing.expect(lut_builder.river_lut.count() > 0);
    try testing.expect(lut_builder.turn_lut.count() > 0);
    try testing.expect(lut_builder.flop_lut.count() > 0);
    
    // Test hand lookup
    const test_hand = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "hearts"),
    };
    
    const test_flop = [_]Card{
        Card.init(2, "spades"),
        Card.init(7, "hearts"),
        Card.init(12, "diamonds"),
    };
    
    // Should be able to find cluster for this hand
    const cluster = try lut_builder.getFlopCluster(&test_hand, &test_flop);
    try testing.expect(cluster > 0 and cluster <= 40);
}

test "memory consistency across components" {
    // Test that all components properly manage memory
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const test_allocator = gpa.allocator();
    
    const initial_memory = gpa.total_requested_bytes;
    
    // Create and use multiple components
    {
        var game_engine = try GameEngine.init(test_allocator, 4);
        defer game_engine.deinit();
        
        try game_engine.dealHoleCards();
        try game_engine.dealFlop();
        
        var equity_calc = EquityCalculator.init(test_allocator);
        const all_cards = try @import("../src/eval_card.zig").generateAllCards(test_allocator);
        defer test_allocator.free(all_cards);
        
        const game_state = game_engine.getGameState();
        _ = try equity_calc.calculateEHS(
            &game_state.players[0].hole_cards,
            &game_state.community_cards,
            all_cards,
            100,
            42,
        );
        
        var cfr_solver = try CFRSolver.init(test_allocator, 2);
        defer cfr_solver.deinit();
        
        var game_tree = try @import("../src/game_tree.zig").GameTree.init(test_allocator);
        defer game_tree.deinit();
        
        // Run a few CFR iterations
        var i: usize = 0;
        while (i < 5) : (i += 1) {
            try cfr_solver.runIteration(&game_tree, i);
        }
    }
    
    const final_memory = gpa.total_requested_bytes;
    
    // Memory should be properly cleaned up
    try testing.expect(final_memory <= initial_memory + 2048); // Allow some overhead
}

test "data consistency between Python and Zig" {
    // Test that core data structures match Python implementation
    
    // Test card creation consistency
    const ace_spades_zig = Card.init(14, "spades");
    
    // Should match Python's card representation pattern
    try testing.expect(ace_spades_zig.rank == 14);
    try testing.expect(std.mem.eql(u8, ace_spades_zig.suit, "spades"));
    
    // Test hand evaluation consistency with known results
    const royal_flush = [_]Card{
        Card.init(14, "spades"), Card.init(13, "spades"), Card.init(12, "spades"),
        Card.init(11, "spades"), Card.init(10, "spades"), Card.init(2, "hearts"),
        Card.init(3, "hearts"),
    };
    
    const rank = HandEvaluator.evaluate7Card(&royal_flush);
    try testing.expect(rank == 1); // Should match Python's royal flush rank
    
    // Test that card generation produces exactly 52 unique cards
    const all_cards = try @import("../src/eval_card.zig").generateAllCards(allocator);
    defer allocator.free(all_cards);
    
    try testing.expect(all_cards.len == 52);
    
    // Verify all cards are unique
    var seen_cards = std.HashMap(u32, void, std.hash_map.DefaultContext(u32), 80).init(allocator);
    defer seen_cards.deinit();
    
    for (all_cards) |card| {
        try testing.expect(!seen_cards.contains(card.eval_card));
        try seen_cards.put(card.eval_card, {});
    }
    
    try testing.expect(seen_cards.count() == 52);
}

test "performance regression detection" {
    // Test that basic operations complete within reasonable time limits
    var timer = try std.time.Timer.start();
    
    // Hand evaluation should be fast
    const hand = [_]Card{
        Card.init(14, "spades"), Card.init(13, "hearts"), Card.init(12, "diamonds"),
        Card.init(11, "clubs"), Card.init(10, "spades"), Card.init(9, "hearts"),
        Card.init(8, "diamonds"),
    };
    
    timer.reset();
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        _ = HandEvaluator.evaluate7Card(&hand);
    }
    const eval_time_ns = timer.read();
    
    // 10k evaluations should complete in under 10ms on modern hardware
    try testing.expect(eval_time_ns < 10_000_000);
    
    // Game engine creation should be fast
    timer.reset();
    i = 0;
    while (i < 1000) : (i += 1) {
        var game_engine = try GameEngine.init(allocator, 6);
        game_engine.deinit();
    }
    const engine_time_ns = timer.read();
    
    // 1k engine creations should complete in under 100ms
    try testing.expect(engine_time_ns < 100_000_000);
}

test "error handling across components" {
    // Test that errors are properly propagated between components
    
    // Test invalid game actions
    var game_engine = try GameEngine.init(allocator, 2);
    defer game_engine.deinit();
    
    try game_engine.dealHoleCards();
    
    // Try to bet more than stack
    const stack_size = game_engine.getGameState().players[0].stack;
    const result = game_engine.playerAction(0, .{ .bet = stack_size + 100 });
    try testing.expectError(error.InsufficientChips, result);
    
    // Test storage errors with invalid database path
    const invalid_path = "/nonexistent/path/database.db";
    const storage_result = Storage.init(allocator, invalid_path, 10);
    try testing.expectError(error.DatabaseError, storage_result);
    
    // Test equity calculation with invalid inputs
    var equity_calc = EquityCalculator.init(allocator);
    
    const empty_cards: []const Card = &[_]Card{};
    const valid_hole = [_]Card{ Card.init(14, "spades"), Card.init(13, "hearts") };
    const valid_board = [_]Card{ Card.init(2, "spades"), Card.init(7, "hearts"), Card.init(12, "diamonds") };
    
    // This should error due to empty card deck
    const equity_result = equity_calc.calculateEHS(&valid_hole, &valid_board, empty_cards, 100, 42);
    try testing.expectError(error.InvalidInput, equity_result);
}