// Performance benchmarks for poker AI system
// Measures key performance characteristics

const std = @import("std");
const poker_ai = @import("poker_ai");
const hand_eval = poker_ai.hand_eval;

pub fn main() !void {
    std.log.info("Poker AI Performance Benchmarks", .{});
    std.log.info("================================", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize poker AI library
    poker_ai.init(allocator);
    defer poker_ai.deinit();
    
    // Run benchmarks
    try benchmarkHandEvaluation(allocator);
    try benchmarkGameStateOperations(allocator);
    try benchmarkMemoryOperations(allocator);
    try benchmarkUtilities(allocator);
    try benchmarkCFRComponents(allocator);
    
    std.log.info("All benchmarks completed!", .{});
}

fn benchmarkHandEvaluation(_: std.mem.Allocator) !void {
    std.log.info("\n=== Hand Evaluation Benchmarks ===", .{});
    
    var evaluator = poker_ai.hand_eval.HandEvaluator.init();
    // No deinit needed for HandEvaluator
    
    // Benchmark 5-card evaluation
    const iterations_5 = 1_000_000;
    const test_hand_5 = [5]u8{ 0, 4, 8, 12, 16 };
    
    const start_5 = std.time.nanoTimestamp();
    for (0..iterations_5) |_| {
        // Convert u8 to Card (u32) for evaluation
        const cards_5 = [5]hand_eval.Card{
            @as(hand_eval.Card, test_hand_5[0]),
            @as(hand_eval.Card, test_hand_5[1]),
            @as(hand_eval.Card, test_hand_5[2]),
            @as(hand_eval.Card, test_hand_5[3]),
            @as(hand_eval.Card, test_hand_5[4]),
        };
        _ = evaluator.evaluateFive(cards_5);
    }
    const end_5 = std.time.nanoTimestamp();
    
    const ns_per_eval_5 = @divTrunc(end_5 - start_5, iterations_5);
    const evals_per_sec_5 = @divTrunc(1_000_000_000, ns_per_eval_5);
    
    std.log.info("5-card evaluation: {}ns per eval, {} evals/sec", .{ ns_per_eval_5, evals_per_sec_5 });
    
    // Benchmark 7-card evaluation
    const iterations_7 = 100_000;
    const test_hand_7 = [7]u8{ 0, 4, 8, 12, 16, 20, 24 };
    
    const start_7 = std.time.nanoTimestamp();
    for (0..iterations_7) |_| {
        // Convert u8 to Card (u32) for evaluation
        const cards_7 = [7]hand_eval.Card{
            @as(hand_eval.Card, test_hand_7[0]),
            @as(hand_eval.Card, test_hand_7[1]),
            @as(hand_eval.Card, test_hand_7[2]),
            @as(hand_eval.Card, test_hand_7[3]),
            @as(hand_eval.Card, test_hand_7[4]),
            @as(hand_eval.Card, test_hand_7[5]),
            @as(hand_eval.Card, test_hand_7[6]),
        };
        _ = evaluator.evaluateSeven(cards_7);
    }
    const end_7 = std.time.nanoTimestamp();
    
    const ns_per_eval_7 = @divTrunc(end_7 - start_7, iterations_7);
    const evals_per_sec_7 = @divTrunc(1_000_000_000, ns_per_eval_7);
    
    std.log.info("7-card evaluation: {}ns per eval, {} evals/sec", .{ ns_per_eval_7, evals_per_sec_7 });
    
    // Memory usage
    // HandEvaluator has lookup_tables field which contains the tables
    // For now we'll estimate the size
    const estimated_table_size = 50000 * @sizeOf(u32); // Rough estimate
    std.log.info("Estimated lookup table memory usage: {} bytes ({} KB)", .{ estimated_table_size, estimated_table_size / 1024 });
}

fn benchmarkGameStateOperations(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== Game State Benchmarks ===", .{});
    
    // Benchmark game state creation/destruction
    const iterations = 100_000;
    
    const start = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        var game = try poker_ai.game_state.GameState.init(allocator, 2, 5, 10);
        game.deinit();
    }
    const end = std.time.nanoTimestamp();
    
    const ns_per_create = @divTrunc(end - start, iterations);
    std.log.info("Game state create/destroy: {}ns per operation", .{ns_per_create});
    
    // Benchmark action application
    var game = try poker_ai.game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    
    const action_iterations = 1_000_000;
    const call_action = poker_ai.game_state.Action.call();
    
    const action_start = std.time.nanoTimestamp();
    for (0..action_iterations) |_| {
        // Reset game state periodically to avoid filling action history
        if (@mod(@as(u32, @intCast(@rem(@as(usize, @intCast(std.time.nanoTimestamp())), 1000))), 100) == 0) {
            game.actions.clearRetainingCapacity();
            game.action_sequence.clearRetainingCapacity();
        }
        _ = game.applyAction(call_action) catch {};
    }
    const action_end = std.time.nanoTimestamp();
    
    const ns_per_action = @divTrunc(action_end - action_start, action_iterations);
    std.log.info("Action application: {}ns per operation", .{ns_per_action});
    
    // Benchmark information set generation
    game.players[0].hand = poker_ai.game_state.Hand.init(0, 1);
    
    const info_iterations = 100_000;
    const info_start = std.time.nanoTimestamp();
    for (0..info_iterations) |_| {
        const info_set = try game.getInfoSet(0);
        allocator.free(info_set);
    }
    const info_end = std.time.nanoTimestamp();
    
    const ns_per_info = @divTrunc(info_end - info_start, info_iterations);
    std.log.info("Info set generation: {}ns per operation", .{ns_per_info});
}

fn benchmarkMemoryOperations(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== Memory Management Benchmarks ===", .{});
    
    // Benchmark strategy table operations
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(allocator);
    defer strategy_table.deinit();
    
    const iterations = 10_000;
    const actions = [_]poker_ai.game_state.ActionType{ .fold, .call, .raise };
    
    const start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        _ = try strategy_table.getOrCreateStrategy(@intCast(i), &actions);
    }
    const end = std.time.nanoTimestamp();
    
    const ns_per_strategy = @divTrunc(end - start, iterations);
    const memory_usage = strategy_table.getMemoryUsage();
    
    std.log.info("Strategy creation: {}ns per operation", .{ns_per_strategy});
    std.log.info("Strategy table memory: {} bytes ({} KB)", .{ memory_usage, memory_usage / 1024 });
    
    // AbstractionTable not yet implemented - skip this benchmark
}

fn benchmarkUtilities(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== Utility Function Benchmarks ===", .{});
    
    // Benchmark hash functions
    const hash_iterations = 1_000_000;
    const test_cards = [_]u8{ 0, 1, 2, 3, 4 };
    
    const hash_start = std.time.nanoTimestamp();
    for (0..hash_iterations) |_| {
        _ = poker_ai.utils.HashUtils.hashCards(&test_cards);
    }
    const hash_end = std.time.nanoTimestamp();
    
    const ns_per_hash = @divTrunc(hash_end - hash_start, hash_iterations);
    std.log.info("Card hashing: {}ns per operation", .{ns_per_hash});
    
    // Benchmark random number generation
    var rng = poker_ai.utils.RandomUtils.FastRng.init(12345);
    
    const rng_iterations = 10_000_000;
    const rng_start = std.time.nanoTimestamp();
    for (0..rng_iterations) |_| {
        _ = rng.next();
    }
    const rng_end = std.time.nanoTimestamp();
    
    const ns_per_rng = @divTrunc(rng_end - rng_start, rng_iterations);
    std.log.info("Random number generation: {}ns per operation", .{ns_per_rng});
    
    // Benchmark bit operations
    const bit_iterations = 100_000_000;
    var test_value: u64 = 0x123456789ABCDEF0;
    
    const bit_start = std.time.nanoTimestamp();
    for (0..bit_iterations) |_| {
        test_value = poker_ai.utils.BitUtils.setBit(test_value, @intCast(@rem(@as(usize, @intCast(std.time.nanoTimestamp())), 64)));
    }
    const bit_end = std.time.nanoTimestamp();
    
    const ns_per_bit = @divTrunc(bit_end - bit_start, bit_iterations);
    std.log.info("Bit manipulation: {}ns per operation", .{ns_per_bit});
    
    // Benchmark string operations
    const string_iterations = 100_000;
    const string_start = std.time.nanoTimestamp();
    for (0..string_iterations) |_| {
        const card_str = try poker_ai.utils.StringUtils.cardsToString(allocator, &test_cards);
        allocator.free(card_str);
    }
    const string_end = std.time.nanoTimestamp();
    
    const ns_per_string = @divTrunc(string_end - string_start, string_iterations);
    std.log.info("Card string conversion: {}ns per operation", .{ns_per_string});
}

fn benchmarkCFRComponents(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== CFR Component Benchmarks ===", .{});
    
    // Benchmark info set node operations
    const iterations = 100_000;
    var node = try poker_ai.cfr.InfoSetNode.init(allocator, "benchmark_node", 3);
    defer node.deinit();
    
    // Set up some regret values
    node.regret_sum[0] = 10.0;
    node.regret_sum[1] = 5.0;
    node.regret_sum[2] = 2.0;
    
    const strategy_start = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        const strategy = try node.getStrategy(1.0);
        allocator.free(strategy);
    }
    const strategy_end = std.time.nanoTimestamp();
    
    const ns_per_strategy = @divTrunc(strategy_end - strategy_start, iterations);
    std.log.info("Strategy calculation: {}ns per operation", .{ns_per_strategy});
    
    // Benchmark action probability operations
    const actions = [_]poker_ai.game_state.ActionType{ .fold, .call, .raise };
    var action_probs = try poker_ai.strategy_table.ActionProbabilities.init(allocator, &actions);
    defer action_probs.deinit();
    
    const prob_iterations = 1_000_000;
    var prng = std.Random.DefaultPrng.init(54321);
    const random = prng.random();
    
    const prob_start = std.time.nanoTimestamp();
    for (0..prob_iterations) |_| {
        _ = action_probs.sampleAction(random);
    }
    const prob_end = std.time.nanoTimestamp();
    
    const ns_per_prob = @divTrunc(prob_end - prob_start, prob_iterations);
    std.log.info("Action sampling: {}ns per operation", .{ns_per_prob});
    
    // Benchmark game state cloning for CFR
    var original_game = try poker_ai.game_state.GameState.init(allocator, 2, 5, 10);
    defer original_game.deinit();
    
    const clone_iterations = 10_000;
    const clone_start = std.time.nanoTimestamp();
    for (0..clone_iterations) |_| {
        var cloned_game = try cloneGameStateForBench(&original_game, allocator);
        cloned_game.deinit();
    }
    const clone_end = std.time.nanoTimestamp();
    
    const ns_per_clone = @divTrunc(clone_end - clone_start, clone_iterations);
    std.log.info("Game state cloning: {}ns per operation", .{ns_per_clone});
}

// Helper function for benchmarking game state cloning
fn cloneGameStateForBench(original: *poker_ai.game_state.GameState, allocator: std.mem.Allocator) !poker_ai.game_state.GameState {
    var clone = try poker_ai.game_state.GameState.init(
        allocator,
        original.num_players,
        original.small_blind,
        original.big_blind,
    );
    
    // Copy essential state
    clone.players = original.players;
    clone.active_players = original.active_players;
    clone.round = original.round;
    clone.board = original.board;
    clone.board_size = original.board_size;
    clone.current_player = original.current_player;
    clone.dealer_button = original.dealer_button;
    clone.pot = original.pot;
    clone.current_bet = original.current_bet;
    clone.last_raiser = original.last_raiser;
    
    return clone;
}

// Performance stress test
fn stressTest(allocator: std.mem.Allocator) !void {
    std.log.info("\n=== Stress Test ===", .{});
    
    const stress_iterations = 1000;
    var total_memory: usize = 0;
    
    var timer = poker_ai.utils.PerfUtils.Timer.start();
    
    for (0..stress_iterations) |_| {
        // Create multiple components simultaneously
        var evaluator = poker_ai.hand_eval.HandEvaluator.init();
        var game = try poker_ai.game_state.GameState.init(allocator, 6, 5, 10);
        var strategy_table = poker_ai.strategy_table.StrategyTable.init(allocator);
        // AbstractionTable not yet implemented
        
        // Use them briefly
        const test_hand = [5]u8{ 0, 1, 2, 3, 4 };
        // Convert u8 to Card (u32) for evaluation
        const cards = [5]hand_eval.Card{
            @as(hand_eval.Card, test_hand[0]),
            @as(hand_eval.Card, test_hand[1]),
            @as(hand_eval.Card, test_hand[2]),
            @as(hand_eval.Card, test_hand[3]),
            @as(hand_eval.Card, test_hand[4]),
        };
        _ = evaluator.evaluateFive(cards);
        
        const action = poker_ai.game_state.Action.call();
        _ = try game.applyAction(action);
        
        const actions = [_]poker_ai.game_state.ActionType{ .fold, .call };
        _ = try strategy_table.getOrCreateStrategy(12345, &actions);
        
        // AbstractionTable operations not yet implemented
        
        // Track memory usage
        total_memory += strategy_table.getMemoryUsage();
        
        // Clean up
        // evaluator has no deinit
        game.deinit();
        strategy_table.deinit();
        // abstraction_table not implemented
    }
    
    const elapsed = timer.elapsedMs();
    const avg_memory = total_memory / stress_iterations;
    
    std.log.info("Stress test completed: {} iterations in {d:.2}ms", .{ stress_iterations, elapsed });
    std.log.info("Average memory per iteration: {} bytes", .{avg_memory});
    std.log.info("Operations per second: {d:.0}", .{ @as(f64, @floatFromInt(stress_iterations)) / (elapsed / 1000.0) });
}