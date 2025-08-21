// Minimal test to verify MCCFR builds and runs
const std = @import("std");

pub fn main() !void {
    std.log.info("Testing MCCFR implementation compilation and basic structure", .{});
    
    // Test that the modules compile
    const cfr = @import("src/cfr.zig");
    const strategy_table = @import("src/strategy_table.zig");
    const game_state = @import("src/game_state.zig");
    
    // Test basic initialization
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create a simple config
    const config = cfr.CFRConfig.default();
    std.log.info("CFRConfig created with {} iterations", .{config.iterations});
    
    // Create strategy table
    var strat_table = strategy_table.StrategyTable.init(allocator);
    defer strat_table.deinit();
    std.log.info("Strategy table initialized", .{});
    
    // Create game state
    var game = try game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    std.log.info("Game state initialized with {} players", .{game.num_players});
    
    // Test info set creation
    const info_set = try game.getInfoSet(0);
    defer allocator.free(info_set);
    std.log.info("Info set generated: {} bytes", .{info_set.len});
    
    std.log.info("All basic components working correctly!", .{});
}