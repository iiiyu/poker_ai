const std = @import("std");
const simple = @import("simple");

const print = std.debug.print;
const CardOps = simple.CardOps;
const Card = simple.Card;

pub fn main() !void {
    print("🃏 Zig Poker Hand Evaluator Demo\n");
    print("================================\n\n");

    // Initialize evaluator
    var evaluator = HandEvaluator.init();
    defer evaluator.lookup_tables.deinit();
    try evaluator.lookup_tables.initTables();

    print("✅ Lookup tables initialized\n");
    print("   Flush entries: {d}\n", .{evaluator.lookup_tables.flush_map.count()});
    print("   Unsuited entries: {d}\n\n", .{evaluator.lookup_tables.unsuited_map.count()});

    // Demo 1: Single hand evaluation
    print("🔥 Demo 1: Single Hand Evaluation\n");
    print("----------------------------------\n");

    const royal_flush = [5]hand_eval.Card{
        CardOps.fromString("As"),
        CardOps.fromString("Ks"),
        CardOps.fromString("Qs"),
        CardOps.fromString("Js"),
        CardOps.fromString("Ts"),
    };

    const rank = evaluator.evaluateFive(royal_flush);
    const hand_type = HandEvaluator.getHandType(rank);
    const type_string = HandEvaluator.handTypeToString(hand_type);

    print("Hand: As Ks Qs Js Ts\n");
    print("Rank: {d} (1 = best, 7462 = worst)\n", .{rank});
    print("Type: {s}\n\n", .{type_string});

    // Demo 2: Multiple hand types
    print("🎯 Demo 2: Various Hand Types\n");
    print("------------------------------\n");

    const test_hands = [_]struct {
        cards: [5]hand_eval.Card,
        description: []const u8,
    }{
        .{
            .cards = [5]hand_eval.Card{
                CardOps.fromString("As"),
                CardOps.fromString("Ah"),
                CardOps.fromString("Ad"),
                CardOps.fromString("Ac"),
                CardOps.fromString("Ks"),
            },
            .description = "Four Aces",
        },
        .{
            .cards = [5]hand_eval.Card{
                CardOps.fromString("As"),
                CardOps.fromString("Ah"),
                CardOps.fromString("Ad"),
                CardOps.fromString("Ks"),
                CardOps.fromString("Kh"),
            },
            .description = "Aces full of Kings",
        },
        .{
            .cards = [5]hand_eval.Card{
                CardOps.fromString("As"),
                CardOps.fromString("Js"),
                CardOps.fromString("9s"),
                CardOps.fromString("7s"),
                CardOps.fromString("2s"),
            },
            .description = "Ace-high flush",
        },
        .{
            .cards = [5]hand_eval.Card{
                CardOps.fromString("As"),
                CardOps.fromString("Kh"),
                CardOps.fromString("Qd"),
                CardOps.fromString("Jc"),
                CardOps.fromString("Ts"),
            },
            .description = "Broadway straight",
        },
        .{
            .cards = [5]hand_eval.Card{
                CardOps.fromString("As"),
                CardOps.fromString("Kh"),
                CardOps.fromString("Qd"),
                CardOps.fromString("Jc"),
                CardOps.fromString("9s"),
            },
            .description = "Ace high",
        },
    };

    for (test_hands) |test_hand| {
        const test_rank = evaluator.evaluateFive(test_hand.cards);
        const test_type = HandEvaluator.getHandType(test_rank);
        const test_type_string = HandEvaluator.handTypeToString(test_type);

        print("{s:<20} | Rank: {d:>4} | Type: {s}\n", .{ test_hand.description, test_rank, test_type_string });
    }

    print("\n");

    // Demo 3: Seven-card Texas Hold'em evaluation
    print("🎰 Demo 3: Texas Hold'em (7 cards → best 5)\n");
    print("--------------------------------------------\n");

    const seven_cards = [7]hand_eval.Card{
        CardOps.fromString("As"), // Hole card 1
        CardOps.fromString("Ks"), // Hole card 2
        CardOps.fromString("Qs"), // Flop card 1
        CardOps.fromString("Js"), // Flop card 2
        CardOps.fromString("Ts"), // Flop card 3
        CardOps.fromString("2h"), // Turn card
        CardOps.fromString("7c"), // River card
    };

    const seven_rank = evaluator.evaluateSeven(seven_cards);
    const seven_type = HandEvaluator.getHandType(seven_rank);
    const seven_type_string = HandEvaluator.handTypeToString(seven_type);

    print("Hole: As Ks\n");
    print("Board: Qs Js Ts 2h 7c\n");
    print("Best 5-card hand rank: {d}\n", .{seven_rank});
    print("Hand type: {s}\n\n", .{seven_type_string});

    // Demo 4: Batch evaluation
    print("⚡ Demo 4: Batch Evaluation Performance\n");
    print("---------------------------------------\n");

    var batch_evaluator = BatchEvaluator.init();
    defer batch_evaluator.evaluator.lookup_tables.deinit();
    try batch_evaluator.evaluator.lookup_tables.initTables();

    const BATCH_SIZE = 1000;
    const batch_hands = try std.heap.page_allocator.alloc([5]hand_eval.Card, BATCH_SIZE);
    defer std.heap.page_allocator.free(batch_hands);
    const batch_results = try std.heap.page_allocator.alloc(hand_eval.HandRank, BATCH_SIZE);
    defer std.heap.page_allocator.free(batch_results);

    // Fill batch with royal flushes for demonstration
    for (batch_hands) |*hand| {
        hand.* = royal_flush;
    }

    const start_time = std.time.nanoTimestamp();
    batch_evaluator.evaluateFiveBatch(batch_hands, batch_results);
    const end_time = std.time.nanoTimestamp();

    const total_ns = @as(u64, @intCast(end_time - start_time));
    const avg_ns = total_ns / BATCH_SIZE;

    print("Evaluated {d} hands in {d} nanoseconds\n", .{ BATCH_SIZE, total_ns });
    print("Average per hand: {d} nanoseconds\n", .{avg_ns});
    print("Throughput: {d} hands per second\n", .{@as(u64, 1_000_000_000) / avg_ns});

    if (avg_ns < 100) {
        print("🎉 Performance target achieved! (< 100ns per hand)\n");
    } else {
        print("🔧 Performance can be improved (target: < 100ns per hand)\n");
    }

    print("\n✨ Demo complete!\n");
}
