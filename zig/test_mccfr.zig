// Simple test program to verify MCCFR implementation
const std = @import("std");
const cfr = @import("src/cfr.zig");
const game_state = @import("src/game_state.zig");
const strategy_table = @import("src/strategy_table.zig");
const lookup_tables = @import("src/lookup_tables.zig");
const hand_eval = @import("src/hand_eval.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("Testing MCCFR Implementation", .{});
    
    // Create configuration for small test
    const config = cfr.CFRConfig{
        .iterations = 10, // Small number for testing
        .exploration_probability = 0.6,
        .prune_threshold = -300.0,
        .discount_alpha = 1.5,
        .discount_beta = 0.0,
    };
    
    // Initialize components
    var strat_table = strategy_table.StrategyTable.init(allocator);
    defer strat_table.deinit();
    
    var abstraction_table = try lookup_tables.AbstractionTable.init(allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = hand_eval.HandEvaluator.init();
    
    // Create MCCFR trainer
    var trainer = try cfr.MCCFRTrainer.init(
        allocator,
        config,
        &strat_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    std.log.info("Starting MCCFR training with {} iterations", .{config.iterations});
    
    // Run training
    try trainer.train();
    
    // Report results
    std.log.info("Training completed!", .{});
    std.log.info("Info sets created: {}", .{trainer.nodes.count()});
    std.log.info("Strategies stored: {}", .{strat_table.strategies.count()});
    
    // Calculate memory usage
    const memory_usage = strat_table.getMemoryUsage();
    std.log.info("Strategy table memory usage: {} bytes", .{memory_usage});
    
    // Save strategies to file
    const strategy_file = "test_strategies.bin";
    try strat_table.saveToFile(strategy_file);
    std.log.info("Strategies saved to {s}", .{strategy_file});
    
    // Clean up file
    defer std.fs.cwd().deleteFile(strategy_file) catch {};
    
    std.log.info("MCCFR test completed successfully!", .{});
}