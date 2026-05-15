//! Minimal test for MCCFR training to isolate issues

const std = @import("std");
const game_state = @import("game_state.zig");
const linear_cfr = @import("linear_cfr.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Starting minimal MCCFR test...\n", .{});
    
    // Create simple trainer
    const config = linear_cfr.LinearCFRConfig{
        .discount_positive = 1.5,
        .discount_negative = 0.5,
        .discount_interval = 100,
        .prune_threshold = -300.0,
        .exploration_epsilon = 0.6,
        .use_averaging = true,
    };
    
    var trainer = try linear_cfr.LinearCFRTrainer.init(allocator, config);
    defer trainer.deinit();
    
    // Create minimal game state
    var game = try game_state.GameState.init(allocator, 2, 1, 2);
    defer game.deinit();
    
    // Initialize with simple setup
    var prng = std.Random.DefaultPrng.init(42);
    game.shuffleDeck(prng.random());
    
    // Deal cards
    var hands: [2][2]game_state.Card = undefined;
    hands[0][0] = game.dealCard();
    hands[0][1] = game.dealCard();
    hands[1][0] = game.dealCard();
    hands[1][1] = game.dealCard();
    
    game.dealHoleCards(hands[0..]);
    
    // Post blinds
    try game.postBlinds();
    
    std.debug.print("Game initialized:\n", .{});
    std.debug.print("  Players: {}\n", .{game.num_players});
    std.debug.print("  Active: {}\n", .{game.active_players});
    std.debug.print("  Pot: {}\n", .{game.pot});
    std.debug.print("  Current bet: {}\n", .{game.current_bet});
    std.debug.print("  Terminal: {}\n", .{game.isTerminal()});
    
    // Test getting legal actions
    const actions = game.getLegalActions();
    std.debug.print("  Legal actions: {}\n", .{actions.len});
    for (actions, 0..) |action, i| {
        std.debug.print("    [{}] {}\n", .{i, action.action_type});
    }
    
    // Try a single iteration
    std.debug.print("\nRunning single MCCFR iteration...\n", .{});
    
    const utility = trainer.iterate(&game) catch |err| {
        std.debug.print("Error during iteration: {}\n", .{err});
        return err;
    };
    
    std.debug.print("Iteration completed! Utility: {d}\n", .{utility});
    std.debug.print("Info sets created: {}\n", .{trainer.infoset_map.count()});
    
    // Try a few more iterations
    std.debug.print("\nRunning 10 more iterations...\n", .{});
    for (0..10) |i| {
        // Reset game for each iteration
        game = try game_state.GameState.init(allocator, 2, 1, 2);
        defer game.deinit();
        
        game.shuffleDeck(prng.random());
        hands[0][0] = game.dealCard();
        hands[0][1] = game.dealCard();
        hands[1][0] = game.dealCard();
        hands[1][1] = game.dealCard();
        game.dealHoleCards(hands[0..]);
        try game.postBlinds();
        
        const u = try trainer.iterate(&game);
        std.debug.print("  Iteration {}: utility = {d:.4}\n", .{i+1, u});
    }
    
    std.debug.print("\nTest completed successfully!\n", .{});
    std.debug.print("Final info sets: {}\n", .{trainer.infoset_map.count()});
}
