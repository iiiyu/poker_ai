const std = @import("std");
const simple = @import("simple");

const print = std.debug.print;
const CardOps = simple.CardOps;
const Card = simple.Card;

pub fn main() !void {
    print("🃏 Zig Poker Hand Evaluator Demo (Basic Version)\n", .{});
    print("===============================================\n\n", .{});

    print("✅ Basic hand evaluator initialized\n\n", .{});

    // Demo 1: Card representation validation
    print("🔥 Demo 1: Card Representation\n", .{});
    print("-------------------------------\n", .{});

    const royal_flush_cards = [5]Card{
        comptime CardOps.fromString("As"),
        comptime CardOps.fromString("Ks"),
        comptime CardOps.fromString("Qs"),
        comptime CardOps.fromString("Js"),
        comptime CardOps.fromString("Ts"),
    };

    print("Hand: As Ks Qs Js Ts (Royal Flush)\n", .{});
    for (royal_flush_cards) |card| {
        print("  Card: 0x{X:0>8} | Rank: {d:2} | Suit: {d} | Prime: {d:2}\n", .{
            card,
            CardOps.getRank(card),
            CardOps.getSuit(card), 
            CardOps.getPrime(card)
        });
    }

    // Demo 2: Prime product calculation
    print("\n🎯 Demo 2: Prime Product Calculation\n", .{});
    print("------------------------------------\n", .{});
    
    const product = CardOps.primeProductFromHand(&royal_flush_cards);
    const expected = @as(u64, 41) * 37 * 31 * 29 * 23; // A, K, Q, J, T primes
    
    print("Prime product: {d}\n", .{product});
    print("Expected:      {d}\n", .{expected});
    print("Match: {}\n", .{product == expected});

    // Demo 3: Hand type classification
    print("\n🏆 Demo 3: Hand Type Classification\n");
    print("-----------------------------------\n");

    const test_ranks = [_]struct {
        rank: simple.HandRank,
        description: []const u8,
    }{
        .{ .rank = 1, .description = "Best possible hand" },
        .{ .rank = 10, .description = "Worst straight flush" },
        .{ .rank = 11, .description = "Best four of a kind" },
        .{ .rank = 166, .description = "Worst four of a kind" },
        .{ .rank = 167, .description = "Best full house" },
        .{ .rank = 1599, .description = "Worst flush" },
        .{ .rank = 1600, .description = "Best straight" },
        .{ .rank = 7462, .description = "Worst possible hand" },
    };

    for (test_ranks) |test_rank| {
        const hand_type = simple.getHandType(test_rank.rank);
        const type_string = simple.handTypeToString(hand_type);
        print("Rank {d:4} | {s:<25} | {s}\n", .{ test_rank.rank, test_rank.description, type_string });
    }

    // Demo 4: Runtime card creation
    print("\n🎲 Demo 4: Runtime Card Creation\n");
    print("--------------------------------\n");

    const card_strings = [_][]const u8{ "As", "Kh", "Qd", "Jc", "Ts", "2c", "7h", "9d" };
    
    print("Creating cards at runtime:\n");
    for (card_strings) |card_str| {
        const card = CardOps.fromStringRuntime(card_str) catch |err| {
            print("Error creating card {s}: {}\n", .{ card_str, err });
            continue;
        };
        print("  {s} -> 0x{X:0>8} | Rank: {d:2} | Suit: {d} | Prime: {d:2}\n", .{
            card_str,
            card, 
            CardOps.getRank(card),
            CardOps.getSuit(card),
            CardOps.getPrime(card)
        });
    }

    // Demo 5: Performance test
    print("\n⚡ Demo 5: Performance Test\n");
    print("---------------------------\n");

    const ITERATIONS = 100000;
    const test_hand = [5]Card{
        comptime CardOps.fromString("As"),
        comptime CardOps.fromString("Ks"),
        comptime CardOps.fromString("Qs"),
        comptime CardOps.fromString("Js"),
        comptime CardOps.fromString("Ts"),
    };

    const start_time = std.time.nanoTimestamp();
    
    var i: u32 = 0;
    var total_product: u64 = 0;
    while (i < ITERATIONS) : (i += 1) {
        total_product += CardOps.primeProductFromHand(&test_hand);
    }
    
    const end_time = std.time.nanoTimestamp();
    const total_ns = @as(u64, @intCast(end_time - start_time));
    const avg_ns = total_ns / ITERATIONS;

    print("Calculated {d} prime products in {d} nanoseconds\n", .{ ITERATIONS, total_ns });
    print("Average per calculation: {d} nanoseconds\n", .{avg_ns});
    print("Throughput: {d} calculations per second\n", .{@as(u64, 1_000_000_000) / avg_ns});
    print("Total products calculated: {d}\n", .{total_product}); // Prevent optimization

    print("\n✨ Basic demo complete!\n");
    print("\n📝 Next Steps:\n");
    print("   1. Implement lookup table generation\n");
    print("   2. Add full hand evaluation\n"); 
    print("   3. Add SIMD batch processing\n");
    print("   4. Validate against Python implementation\n");
}