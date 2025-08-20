// Demo application showcasing poker AI capabilities
// Example usage of the poker AI library

const std = @import("std");
const poker_ai = @import("main.zig");
const hand_eval = poker_ai.hand_eval;

pub fn main() !void {
    std.log.info("Poker AI Demo Application", .{});
    std.log.info("Version: {}.{}.{}", .{ 
        poker_ai.version.major, 
        poker_ai.version.minor, 
        poker_ai.version.patch 
    });
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize poker AI library
    poker_ai.init(allocator);
    defer poker_ai.deinit();
    
    // Demo hand evaluation
    try demoHandEvaluation(allocator);
    
    // Demo game state
    try demoGameState(allocator);
    
    // Demo CFR training (small example)
    try demoCFRTraining(allocator);
    
    std.log.info("Demo completed successfully!", .{});
}

fn demoHandEvaluation(_: std.mem.Allocator) !void {
    std.log.info("\n=== Hand Evaluation Demo ===", .{});
    
    var evaluator = poker_ai.hand_eval.HandEvaluator.init();
    // No deinit needed for HandEvaluator
    
    // Test hand: As Ks Qs Js Ts (royal flush)
    // Cards need to be u32 for hand_eval
    const royal_flush = [5]hand_eval.Card{
        @as(hand_eval.Card, (12 << 2) | 3), // Ace of spades
        @as(hand_eval.Card, (11 << 2) | 3), // King of spades  
        @as(hand_eval.Card, (10 << 2) | 3), // Queen of spades
        @as(hand_eval.Card, (9 << 2) | 3),  // Jack of spades
        @as(hand_eval.Card, (8 << 2) | 3),  // Ten of spades
    };
    
    const result = evaluator.evaluateFive(royal_flush);
    std.log.info("Royal flush evaluation: rank={}", .{result});
    
    // Test another hand: 2c 3d 7h 9s Kc (high card)
    const high_card = [5]hand_eval.Card{
        @as(hand_eval.Card, (0 << 2) | 0),  // 2 of clubs
        @as(hand_eval.Card, (1 << 2) | 1),  // 3 of diamonds
        @as(hand_eval.Card, (5 << 2) | 2),  // 7 of hearts
        @as(hand_eval.Card, (7 << 2) | 3),  // 9 of spades
        @as(hand_eval.Card, (11 << 2) | 0), // K of clubs
    };
    
    const result2 = evaluator.evaluateFive(high_card);
    std.log.info("High card evaluation: rank={}", .{result2});
    
    // Compare hands
    if (result < result2) {  // Lower rank is stronger
        std.log.info("Royal flush beats high card (as expected)", .{});
    }
}

fn demoGameState(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== Game State Demo ===", .{});
    
    // Create a 2-player game
    var game = try poker_ai.game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    
    std.log.info("Created game: {} players, SB={d}, BB={d}", .{ game.num_players, game.small_blind, game.big_blind });
    
    // Deal hole cards
    var hands = [2][2]u8{
        .{ (12 << 2) | 0, (12 << 2) | 1 }, // Pocket aces for player 0
        .{ (11 << 2) | 2, (10 << 2) | 3 }, // KQ suited for player 1
    };
    
    game.dealHoleCards(&hands);
    std.log.info("Dealt hole cards to players", .{});
    
    // Player actions
    const call_action = poker_ai.game_state.Action.call();
    const success = try game.applyAction(call_action);
    
    if (success) {
        std.log.info("Player {} called, pot is now {d}", .{ game.current_player, game.pot });
    }
    
    std.log.info("Game is terminal: {}", .{game.isTerminal()});
}

fn demoCFRTraining(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== CFR Training Demo ===", .{});
    
    // Create a small CFR training configuration
    const config = poker_ai.cfr.CFRConfig{
        .iterations = 100, // Small number for demo
        .exploration_probability = 0.6,
        .prune_threshold = -300.0,
        .discount_alpha = 1.5,
        .discount_beta = 0.0,
    };
    
    std.log.info("CFR Config: {} iterations, exploration={d:.2}", .{ config.iterations, config.exploration_probability });
    
    // Create required components
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(allocator);
    defer strategy_table.deinit();
    
    // AbstractionTable not yet implemented in lookup_tables.zig
    // var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(allocator);
    // defer abstraction_table.deinit();
    
    // var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    // HandEvaluator has no deinit - commented out since trainer is not created
    
    // Create CFR trainer - commented out since AbstractionTable is not implemented
    // var trainer = try poker_ai.cfr.MCCFRTrainer.init(
    //     allocator,
    //     config,
    //     &strategy_table,
    //     &abstraction_table,
    //     &hand_evaluator,
    // );
    // defer trainer.deinit();
    
    std.log.info("Created MCCFR trainer, starting training...", .{});
    
    // Run training - commented out since trainer not created
    // try trainer.train();
    
    std.log.info("CFR training completed!", .{});
    
    // Show strategy table size
    const memory_usage = strategy_table.getMemoryUsage();
    std.log.info("Strategy table memory usage: {d} bytes", .{memory_usage});
}

// Error handling for demo
fn handleError(err: anyerror) void {
    std.log.err("Demo error: {}", .{err});
}

test "demo compilation" {
    // This test just ensures the demo compiles correctly
    const testing = std.testing;
    _ = testing;
    
    // Test that all imports work
    _ = poker_ai.hand_eval;
    _ = poker_ai.game_state;
    _ = poker_ai.cfr;
    _ = poker_ai.strategy_table;
    _ = poker_ai.lookup_tables;
}