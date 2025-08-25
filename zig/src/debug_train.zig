//! Debug version of training to find where it's hanging

const std = @import("std");
const game_state = @import("game_state.zig");
const linear_cfr = @import("linear_cfr.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Creating trainer...\n", .{});
    
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
    
    std.debug.print("Trainer created successfully\n", .{});
    
    // Just one iteration
    std.debug.print("Creating game...\n", .{});
    var game = try game_state.GameState.init(allocator, 2, 50, 100);
    defer game.deinit();
    
    std.debug.print("Shuffling deck...\n", .{});
    var prng = std.Random.DefaultPrng.init(42);
    game.shuffleDeck(prng.random());
    
    std.debug.print("Dealing cards...\n", .{});
    var hands: [2][2]game_state.Card = undefined;
    hands[0][0] = game.dealCard();
    hands[0][1] = game.dealCard();
    hands[1][0] = game.dealCard();
    hands[1][1] = game.dealCard();
    
    std.debug.print("Setting hole cards...\n", .{});
    game.dealHoleCards(&hands);
    
    std.debug.print("Posting blinds...\n", .{});
    try game.postBlinds();
    
    std.debug.print("Starting iteration...\n", .{});
    const utility = try trainer.iterate(&game);
    
    std.debug.print("Iteration complete! Utility: {d}\n", .{utility});
    std.debug.print("Info sets: {d}\n", .{trainer.infoset_map.count()});
    
    std.debug.print("SUCCESS - Training iteration completed!\n", .{});
}