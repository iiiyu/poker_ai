// Demo application showcasing poker AI capabilities
// Example usage of the poker AI library

const std = @import("std");
const poker_ai = @import("main.zig");
const hand_eval = poker_ai.hand_eval;

// Helper function to ensure output is always visible in all build modes
fn print(comptime fmt: []const u8, args: anytype) void {
    // Use std.debug.print which works in all build modes including ReleaseFast
    std.debug.print(fmt ++ "\n", args);
}

pub fn main() !void {
    // Use both std.log and print to ensure visibility
    print("Poker AI Demo Application", .{});
    print("Version: {}.{}.{}", .{ 
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
    
    print("Demo completed successfully!", .{});
}

fn demoHandEvaluation(_: std.mem.Allocator) !void {
    print("\n=== Hand Evaluation Demo ===", .{});
    
    var evaluator = poker_ai.hand_eval.HandEvaluator.init();
    defer evaluator.lookup_tables.deinit();
    
    // Test hand: As Ks Qs Js Ts (royal flush)
    // Use the runtime CardOps.fromStringRuntime method
    const royal_flush = [5]hand_eval.Card{
        try poker_ai.hand_eval.CardOps.fromStringRuntime("As"), // Ace of spades
        try poker_ai.hand_eval.CardOps.fromStringRuntime("Ks"), // King of spades  
        try poker_ai.hand_eval.CardOps.fromStringRuntime("Qs"), // Queen of spades
        try poker_ai.hand_eval.CardOps.fromStringRuntime("Js"), // Jack of spades
        try poker_ai.hand_eval.CardOps.fromStringRuntime("Ts"), // Ten of spades
    };
    
    const result = evaluator.evaluateFive(royal_flush);
    const hand_type = poker_ai.hand_eval.HandEvaluator.getHandType(result);
    print("Royal flush evaluation: rank={}, type={s}", .{result, poker_ai.hand_eval.HandEvaluator.handTypeToString(hand_type)});
    
    // Test another hand: 2c 3d 7h 9s Kc (high card)
    const high_card = [5]hand_eval.Card{
        try poker_ai.hand_eval.CardOps.fromStringRuntime("2c"), // 2 of clubs
        try poker_ai.hand_eval.CardOps.fromStringRuntime("3d"), // 3 of diamonds
        try poker_ai.hand_eval.CardOps.fromStringRuntime("7h"), // 7 of hearts
        try poker_ai.hand_eval.CardOps.fromStringRuntime("9s"), // 9 of spades
        try poker_ai.hand_eval.CardOps.fromStringRuntime("Kc"), // K of clubs
    };
    
    const result2 = evaluator.evaluateFive(high_card);
    const hand_type2 = poker_ai.hand_eval.HandEvaluator.getHandType(result2);
    print("High card evaluation: rank={}, type={s}", .{result2, poker_ai.hand_eval.HandEvaluator.handTypeToString(hand_type2)});
    
    // Compare hands
    if (result < result2) {  // Lower rank is stronger
        print("Royal flush beats high card (as expected)", .{});
    } else {
        print("WARNING: Hand evaluation is not working correctly!", .{});
    }
}

fn demoGameState(allocator: std.mem.Allocator) !void {
    print("\n=== Game State Demo ===", .{});
    
    // Create a 2-player game
    var game = try poker_ai.game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    
    print("Created game: {} players, SB={d}, BB={d}", .{ game.num_players, game.small_blind, game.big_blind });
    
    // Post blinds to initialize betting
    try game.postBlinds();
    print("Posted blinds: SB={d}, BB={d}, pot={d}", .{ game.small_blind, game.big_blind, game.pot });
    
    // Deal hole cards
    var hands = [2][2]u8{
        .{ (12 << 2) | 0, (12 << 2) | 1 }, // Pocket aces for player 0
        .{ (11 << 2) | 2, (10 << 2) | 3 }, // KQ suited for player 1
    };
    
    game.dealHoleCards(&hands);
    print("Dealt hole cards to players", .{});
    print("Current player: {d}, current bet: {d}", .{ game.current_player, game.current_bet });
    
    // Player actions
    const call_action = poker_ai.game_state.Action.call();
    const current_player_before = game.current_player;
    const success = try game.applyAction(call_action);
    
    if (success) {
        print("Player {d} called, pot is now {d}", .{ current_player_before, game.pot });
    }
    
    print("Game is terminal: {}", .{game.isTerminal()});
}

fn demoCFRTraining(allocator: std.mem.Allocator) !void {
    print("\n=== CFR Training Demo ===", .{});
    
    // Create a small CFR training configuration
    const config = poker_ai.cfr.CFRConfig{
        .iterations = 100, // Small number for demo
        .exploration_probability = 0.6,
        .prune_threshold = -300.0,
        .discount_alpha = 1.5,
        .discount_beta = 0.0,
    };
    
    print("CFR Config: {} iterations, exploration={d:.2}", .{ config.iterations, config.exploration_probability });
    
    // Create required components
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(allocator);
    defer strategy_table.deinit();
    
    // AbstractionTable now implemented
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    defer hand_evaluator.lookup_tables.deinit();
    
    // Create CFR trainer
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        allocator,
        config,
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    print("Created MCCFR trainer, starting training...", .{});
    
    // Run training
    try trainer.train();
    
    print("CFR training completed!", .{});
    
    // Show strategy table size
    const memory_usage = strategy_table.getMemoryUsage();
    print("Strategy table memory usage: {d} bytes", .{memory_usage});
}

// Error handling for demo
fn handleError(err: anyerror) void {
    print("Demo error: {}", .{err});
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