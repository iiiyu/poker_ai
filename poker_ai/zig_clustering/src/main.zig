const std = @import("std");
const Card = @import("eval_card.zig").Card;
const Storage = @import("storage.zig").Storage;
const LUTBuilder = @import("lut_builder.zig").LUTBuilder;

// Configuration for clustering
const Config = struct {
    // Clustering parameters
    n_river_clusters: usize = 200,
    n_turn_clusters: usize = 200,
    n_flop_clusters: usize = 200,
    n_preflop_clusters: usize = 169,
    
    // Memory management
    chunk_size: usize = 10,
    
    // Coverage limits (how many combinations to generate)
    max_river_combos: usize = 1000,
    max_turn_combos: usize = 1000,
    max_flop_combos: usize = 1000,
    
    // Database
    db_path: []const u8 = "clustering_lut.db",
    
    // Mode
    emergency_mode: bool = false,
    coverage_mode: CoverageMode = .Test,
};

pub const CoverageMode = enum {
    Test,      // 1k combos (fast, for testing)
    Light,     // 10k combos
    Medium,    // 100k combos  
    Heavy,     // 1M combos
    Full,      // All combos (warning: very slow and memory intensive)
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    var config = Config{};
    
    // Check for modes
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "emergency")) {
            config.emergency_mode = true;
            // Reduce parameters for minimal memory usage
            config.n_river_clusters = 10;
            config.n_turn_clusters = 50;
            config.n_flop_clusters = 150;
            config.coverage_mode = .Test;
            std.debug.print("🚨 EMERGENCY MODE - Minimal memory usage\n", .{});
        } else if (std.mem.eql(u8, arg, "test")) {
            // Run tests and exit
            return runTests(allocator);
        } else if (std.mem.eql(u8, arg, "light")) {
            config.coverage_mode = .Light;
            config.max_river_combos = 10000;
            config.max_turn_combos = 10000;
            config.max_flop_combos = 10000;
            config.chunk_size = 100;
            std.debug.print("💡 LIGHT MODE - 10k combinations per stage\n", .{});
        } else if (std.mem.eql(u8, arg, "medium")) {
            config.coverage_mode = .Medium;
            config.max_river_combos = 100000;
            config.max_turn_combos = 50000;
            config.max_flop_combos = 50000;
            config.chunk_size = 1000;
            std.debug.print("⚡ MEDIUM MODE - 50-100k combinations per stage\n", .{});
        } else if (std.mem.eql(u8, arg, "heavy")) {
            config.coverage_mode = .Heavy;
            config.max_river_combos = 1000000;
            config.max_turn_combos = 500000;
            config.max_flop_combos = 500000;
            config.chunk_size = 10000;
            std.debug.print("🔥 HEAVY MODE - 500k-1M combinations per stage\n", .{});
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return;
        }
    }
    
    // Print header
    printHeader(&config);
    
    // Initialize storage
    var storage = try Storage.init(allocator, config.db_path, config.chunk_size);
    defer storage.deinit();
    
    // Initialize LUT builder with coverage limits
    var lut_builder = try LUTBuilder.init(
        allocator,
        &storage,
        config.n_river_clusters,
        config.n_turn_clusters,
        config.n_flop_clusters,
        config.n_preflop_clusters,
    );
    defer lut_builder.deinit();
    
    // Set coverage limits
    lut_builder.max_river_combos = config.max_river_combos;
    lut_builder.max_turn_combos = config.max_turn_combos;
    lut_builder.max_flop_combos = config.max_flop_combos;
    
    // Build LUTs in order (River -> Turn -> Flop)
    // Each stage depends on the previous one
    
    std.debug.print("\n🎯 Starting LUT Generation...\n", .{});
    
    // 1. Build River LUT (simplest - just EHS values)
    try lut_builder.buildRiverLUT();
    
    // 2. Build Turn LUT (depends on River clusters)
    try lut_builder.buildTurnLUT();
    
    // 3. Build Flop LUT (depends on Turn clusters)
    try lut_builder.buildFlopLUT();
    
    std.debug.print("\n✅ LUT Generation Complete!\n", .{});
    std.debug.print("Database: {s}\n", .{config.db_path});
    std.debug.print("River entries: {}\n", .{lut_builder.river_lut.count()});
    std.debug.print("Turn entries: {}\n", .{lut_builder.turn_lut.count()});
    std.debug.print("Flop entries: {}\n", .{lut_builder.flop_lut.count()});
}

fn printHeader(config: *const Config) void {
    std.debug.print("\n{s}\n", .{"=" ** 70});
    std.debug.print("  ZIG POKER CLUSTERING - LUT BUILDER\n", .{});
    std.debug.print("  Texas Hold'em Hand Abstraction System\n", .{});
    std.debug.print("{s}\n", .{"=" ** 70});
    std.debug.print("\nConfiguration:\n", .{});
    std.debug.print("  River clusters: {}\n", .{config.n_river_clusters});
    std.debug.print("  Turn clusters: {}\n", .{config.n_turn_clusters});
    std.debug.print("  Flop clusters: {}\n", .{config.n_flop_clusters});
    std.debug.print("  Preflop clusters: {}\n", .{config.n_preflop_clusters});
    std.debug.print("  Chunk size: {} (flush every {} operations)\n", .{ config.chunk_size, config.chunk_size });
    std.debug.print("  Database: {s}\n", .{config.db_path});
    
    std.debug.print("\nCoverage:\n", .{});
    std.debug.print("  River combinations: {}\n", .{config.max_river_combos});
    std.debug.print("  Turn combinations: {}\n", .{config.max_turn_combos});
    std.debug.print("  Flop combinations: {}\n", .{config.max_flop_combos});
    
    if (config.emergency_mode) {
        std.debug.print("  Mode: EMERGENCY (minimal memory)\n", .{});
    } else {
        const mode_str = switch (config.coverage_mode) {
            .Test => "Test (1k combos)",
            .Light => "Light (10k combos)",
            .Medium => "Medium (50-100k combos)",
            .Heavy => "Heavy (500k-1M combos)",
            .Full => "Full (all combos)",
        };
        std.debug.print("  Mode: {s}\n", .{mode_str});
    }
}

fn printUsage() void {
    std.debug.print("\nUsage: ./main [mode]\n", .{});
    std.debug.print("\nModes:\n", .{});
    std.debug.print("  test      - Run test suite\n", .{});
    std.debug.print("  emergency - Minimal memory usage (1k combos)\n", .{});
    std.debug.print("  light     - Light coverage (10k combos)\n", .{});
    std.debug.print("  medium    - Medium coverage (50-100k combos)\n", .{});
    std.debug.print("  heavy     - Heavy coverage (500k-1M combos)\n", .{});
    std.debug.print("  (default) - Test mode (1k combos)\n", .{});
    std.debug.print("\nExample: ./main medium\n", .{});
}

fn runTests(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 Running Tests...\n", .{});
    std.debug.print("{s}\n", .{"=" ** 50});
    
    // Test 1: Card creation and evaluation
    try testCardSystem(allocator);
    
    // Test 2: Hand evaluation
    try testHandEvaluation(allocator);
    
    // Test 3: EHS calculation
    try testEHSCalculation(allocator);
    
    // Test 4: Storage
    try testStorage(allocator);
    
    std.debug.print("\n✅ All tests passed!\n", .{});
}

fn testCardSystem(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📝 Testing Card System...\n", .{});
    
    // Test card creation
    const ace_spades = Card.init(14, "spades");
    const two_hearts = Card.init(2, "hearts");
    
    std.debug.print("  Ace of Spades eval: {}\n", .{ace_spades.eval_card});
    std.debug.print("  Two of Hearts eval: {}\n", .{two_hearts.eval_card});
    
    // Test card generation
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
    defer allocator.free(all_cards);
    
    std.debug.print("  Generated {} cards\n", .{all_cards.len});
    
    // Verify first card is 2 of spades
    if (all_cards[0].rank != 2 or !std.mem.eql(u8, all_cards[0].suit, "spades")) {
        return error.CardOrderingWrong;
    }
    
    std.debug.print("  ✓ Card ordering correct (suit-first)\n", .{});
}

fn testHandEvaluation(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📝 Testing Hand Evaluation...\n", .{});
    
    const HandEvaluator = @import("evaluator.zig").HandEvaluator;
    
    // Test case 1: Flush beats Pair
    const flush_hand = [_]Card{
        Card.init(2, "hearts"),
        Card.init(5, "hearts"),
        Card.init(7, "hearts"),
        Card.init(9, "hearts"),
        Card.init(10, "hearts"),
        Card.init(3, "diamonds"),
        Card.init(4, "clubs"),
    };
    
    const pair_hand = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "diamonds"),
        Card.init(7, "hearts"),
        Card.init(9, "hearts"),
        Card.init(10, "hearts"),
        Card.init(3, "diamonds"),
        Card.init(4, "clubs"),
    };
    
    const flush_rank = HandEvaluator.evaluate7Card(&flush_hand);
    const pair_rank = HandEvaluator.evaluate7Card(&pair_hand);
    
    std.debug.print("  Flush rank: {}\n", .{flush_rank});
    std.debug.print("  Pair rank: {}\n", .{pair_rank});
    
    if (flush_rank >= pair_rank) {
        std.debug.print("  ❌ Flush should beat pair!\n", .{});
        return error.HandEvaluationWrong;
    }
    
    std.debug.print("  ✓ Flush beats pair (lower rank = better)\n", .{});
    
    _ = allocator;
}

fn testEHSCalculation(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📝 Testing EHS Calculation...\n", .{});
    
    const EquityCalculator = @import("equity_calculator.zig").EquityCalculator;
    
    var calc = EquityCalculator.init(allocator);
    
    // Test: AA on dry board
    const our_hand = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "hearts"),
    };
    
    const board = [_]Card{
        Card.init(2, "spades"),
        Card.init(3, "hearts"),
        Card.init(5, "diamonds"),
    };
    
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
    defer allocator.free(all_cards);
    
    const ehs = try calc.calculateEHS(&our_hand, &board, all_cards, 100, 42);
    
    std.debug.print("  AA on dry board EHS: {:.3}\n", .{ehs});
    
    if (ehs < 0.7 or ehs > 1.0) {
        std.debug.print("  ❌ AA should have high EHS (>0.7)\n", .{});
        return error.EHSCalculationWrong;
    }
    
    std.debug.print("  ✓ EHS calculation reasonable\n", .{});
}

fn testStorage(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📝 Testing Storage...\n", .{});
    
    // Create test database
    const test_db = "test_clustering.db";
    defer std.fs.cwd().deleteFile(test_db) catch {};
    
    var storage = try Storage.init(allocator, test_db, 5);
    defer storage.deinit();
    
    // Test storing river data
    const test_combo = LUTBuilder.Combination{
        .hand = try allocator.dupe(Card, &[_]Card{
            Card.init(14, "spades"),
            Card.init(14, "hearts"),
        }),
        .board = try allocator.dupe(Card, &[_]Card{
            Card.init(2, "spades"),
            Card.init(3, "hearts"),
            Card.init(5, "diamonds"),
            Card.init(7, "clubs"),
            Card.init(9, "spades"),
        }),
    };
    defer allocator.free(test_combo.hand);
    defer allocator.free(test_combo.board);
    
    try storage.storeRiverData(0, test_combo, 0.85, null);
    try storage.flush();
    
    std.debug.print("  ✓ Storage operations successful\n", .{});
}

// Tests embedded in source files
test {
    std.testing.refAllDecls(@This());
    _ = @import("eval_card.zig");
    _ = @import("evaluator.zig");
    _ = @import("equity_calculator.zig");
    _ = @import("game_engine.zig");
    _ = @import("lut_builder.zig");
    _ = @import("storage.zig");
}