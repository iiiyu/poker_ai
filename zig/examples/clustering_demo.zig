const std = @import("std");
const poker_ai = @import("poker_ai");
const clustering = poker_ai.clustering;
const hand_eval = poker_ai.hand_eval;
const lookup_tables = poker_ai.lookup_tables;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Poker Hand Clustering Demo ===\n\n", .{});

    // Initialize hand evaluator
    var evaluator = hand_eval.HandEvaluator.init();

    // Initialize abstraction table with clustering
    var abstraction_table = try lookup_tables.AbstractionTable.init(allocator);
    defer abstraction_table.deinit();

    std.debug.print("Initializing clustering with:\n", .{});
    std.debug.print("  - Preflop clusters: 8\n", .{});
    std.debug.print("  - Flop clusters: 50\n", .{});
    std.debug.print("  - Turn clusters: 50\n", .{});
    std.debug.print("  - River clusters: 50\n\n", .{});

    // Initialize clustering
    try abstraction_table.initClustering(&evaluator, 8, 50, 50, 50);

    // Demo preflop clustering
    std.debug.print("=== Preflop Clustering Examples ===\n\n", .{});

    const test_hands = [_]struct { name: []const u8, c1: []const u8, c2: []const u8 }{
        .{ .name = "Pocket Aces", .c1 = "As", .c2 = "Ah" },
        .{ .name = "Pocket Kings", .c1 = "Ks", .c2 = "Kh" },
        .{ .name = "Ace King suited", .c1 = "As", .c2 = "Ks" },
        .{ .name = "Ace King offsuit", .c1 = "As", .c2 = "Kh" },
        .{ .name = "Queen Jack suited", .c1 = "Qs", .c2 = "Js" },
        .{ .name = "Seven Deuce offsuit", .c1 = "7h", .c2 = "2d" },
        .{ .name = "Pocket Fives", .c1 = "5s", .c2 = "5h" },
        .{ .name = "Ten Nine suited", .c1 = "Ts", .c2 = "9s" },
    };

    for (test_hands) |hand| {
        const c1 = try hand_eval.CardOps.fromStringRuntime(hand.c1);
        const c2 = try hand_eval.CardOps.fromStringRuntime(hand.c2);
        const hole_cards = [2]hand_eval.Card{ c1, c2 };
        const board = [_]hand_eval.Card{}; // Empty board for preflop

        const cluster = try abstraction_table.getHandCluster(hole_cards, &board);
        std.debug.print("{s:20} ({s} {s}): Cluster {d}\n", .{ hand.name, hand.c1, hand.c2, cluster });
    }

    // Demo postflop clustering
    std.debug.print("\n=== Postflop Clustering Examples ===\n\n", .{});

    // Example flop
    const flop_cards = [_]hand_eval.Card{
        try hand_eval.CardOps.fromStringRuntime("Kd"),
        try hand_eval.CardOps.fromStringRuntime("Qh"),
        try hand_eval.CardOps.fromStringRuntime("Js"),
    };

    std.debug.print("Board: Kd Qh Js\n\n", .{});

    const postflop_hands = [_]struct { name: []const u8, c1: []const u8, c2: []const u8 }{
        .{ .name = "Top pair (AK)", .c1 = "As", .c2 = "Kc" },
        .{ .name = "Two pair (KQ)", .c1 = "Ks", .c2 = "Qc" },
        .{ .name = "Straight draw (AT)", .c1 = "Ah", .c2 = "Ts" },
        .{ .name = "Set (JJ)", .c1 = "Jc", .c2 = "Jh" },
        .{ .name = "Nothing (72)", .c1 = "7h", .c2 = "2d" },
    };

    for (postflop_hands) |hand| {
        const c1 = try hand_eval.CardOps.fromStringRuntime(hand.c1);
        const c2 = try hand_eval.CardOps.fromStringRuntime(hand.c2);
        const hole_cards = [2]hand_eval.Card{ c1, c2 };

        const cluster = try abstraction_table.getHandCluster(hole_cards, &flop_cards);
        std.debug.print("{s:20} ({s} {s}): Cluster {d}\n", .{ hand.name, hand.c1, hand.c2, cluster });
    }

    // Demo feature extraction
    std.debug.print("\n=== Feature Extraction Example ===\n\n", .{});

    const demo_hole = [2]hand_eval.Card{
        try hand_eval.CardOps.fromStringRuntime("As"),
        try hand_eval.CardOps.fromStringRuntime("Ks"),
    };

    var feature_extractor = clustering.FeatureExtractor.init(
        allocator,
        &evaluator,
        100, // 100 simulations
    );

    const features = try feature_extractor.extractFeatures(demo_hole, &flop_cards);

    std.debug.print("Hand: As Ks on board Kd Qh Js\n", .{});
    std.debug.print("Features:\n", .{});
    std.debug.print("  - Expected Hand Strength (EHS): {d:.3}\n", .{features.ehs});
    std.debug.print("  - Positive Potential: {d:.3}\n", .{features.positive_potential});
    std.debug.print("  - Negative Potential: {d:.3}\n", .{features.negative_potential});
    std.debug.print("  - Immediate Strength: {d:.3}\n", .{features.immediate_strength});
    std.debug.print("  - Draw Potential: {d:.3}\n", .{features.draw_potential});

    // Demo saving/loading clusters
    std.debug.print("\n=== Cluster Persistence ===\n\n", .{});

    const cluster_file = "poker_clusters.dat";
    std.debug.print("Saving clusters to {s}...\n", .{cluster_file});
    try abstraction_table.saveClusteringData(cluster_file);

    std.debug.print("Loading clusters from {s}...\n", .{cluster_file});
    try abstraction_table.loadClusteringData(cluster_file);

    std.debug.print("\nClustering demo complete!\n", .{});
}
