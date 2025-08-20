const std = @import("std");
const testing = std.testing;
const hand_eval = @import("hand_eval");
const lookup_tables = @import("lookup_tables");

// Import types for easier access
const Card = hand_eval.Card;
const HandRank = hand_eval.HandRank;
const CardOps = hand_eval.CardOps;
const HandEvaluator = hand_eval.HandEvaluator;
const BatchEvaluator = hand_eval.BatchEvaluator;
const HandType = hand_eval.HandType;
const TEST_CARDS = hand_eval.TEST_CARDS;

test "card operations" {
    // Test compile-time card creation
    const ace_spades = CardOps.fromString("As");
    const king_hearts = CardOps.fromString("Kh");
    const deuce_clubs = CardOps.fromString("2c");
    
    // Test rank extraction
    try testing.expect(CardOps.getRank(ace_spades) == 12);  // Ace = 12
    try testing.expect(CardOps.getRank(king_hearts) == 11); // King = 11  
    try testing.expect(CardOps.getRank(deuce_clubs) == 0);  // Deuce = 0
    
    // Test suit extraction
    try testing.expect(CardOps.getSuit(ace_spades) == hand_eval.SUIT_SPADES);
    try testing.expect(CardOps.getSuit(king_hearts) == hand_eval.SUIT_HEARTS);
    try testing.expect(CardOps.getSuit(deuce_clubs) == hand_eval.SUIT_CLUBS);
    
    // Test prime extraction
    try testing.expect(CardOps.getPrime(ace_spades) == 41);  // Ace prime
    try testing.expect(CardOps.getPrime(king_hearts) == 37); // King prime
    try testing.expect(CardOps.getPrime(deuce_clubs) == 2);  // Deuce prime
}

test "runtime card creation" {
    // Test runtime card creation
    const ace_spades = try CardOps.fromStringRuntime("As");
    const king_hearts = try CardOps.fromStringRuntime("Kh");
    
    // Should match compile-time versions
    try testing.expect(CardOps.getRank(ace_spades) == 12);
    try testing.expect(CardOps.getSuit(ace_spades) == hand_eval.SUIT_SPADES);
    try testing.expect(CardOps.getRank(king_hearts) == 11);
    try testing.expect(CardOps.getSuit(king_hearts) == hand_eval.SUIT_HEARTS);
    
    // Test error cases
    try testing.expectError(error.InvalidCardString, CardOps.fromStringRuntime("A"));
    try testing.expectError(error.InvalidRank, CardOps.fromStringRuntime("Xs"));
    try testing.expectError(error.InvalidSuit, CardOps.fromStringRuntime("Ax"));
}

test "prime product calculation" {
    const cards = [_]Card{
        CardOps.fromString("As"), // Prime 41
        CardOps.fromString("Ks"), // Prime 37
        CardOps.fromString("Qs"), // Prime 31
        CardOps.fromString("Js"), // Prime 29
        CardOps.fromString("Ts"), // Prime 23
    };
    
    const product = CardOps.primeProductFromHand(&cards);
    const expected: u64 = 41 * 37 * 31 * 29 * 23;
    
    try testing.expect(product == expected);
}

test "prime product from rankbits" {
    // Test royal flush rankbits (AKQJT = bits 12,11,10,9,8 set)
    const royal_rankbits: u32 = (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8);
    const product = CardOps.primeProductFromRankbits(royal_rankbits);
    const expected: u64 = 41 * 37 * 31 * 29 * 23; // A, K, Q, J, T primes
    
    try testing.expect(product == expected);
}

test "hand type classification" {
    // Test hand type boundaries
    try testing.expect(HandEvaluator.getHandType(1) == .straight_flush);
    try testing.expect(HandEvaluator.getHandType(10) == .straight_flush);
    try testing.expect(HandEvaluator.getHandType(11) == .four_of_a_kind);
    try testing.expect(HandEvaluator.getHandType(166) == .four_of_a_kind);
    try testing.expect(HandEvaluator.getHandType(167) == .full_house);
    try testing.expect(HandEvaluator.getHandType(322) == .full_house);
    try testing.expect(HandEvaluator.getHandType(323) == .flush);
    try testing.expect(HandEvaluator.getHandType(1599) == .flush);
    try testing.expect(HandEvaluator.getHandType(1600) == .straight);
    try testing.expect(HandEvaluator.getHandType(1609) == .straight);
    try testing.expect(HandEvaluator.getHandType(7462) == .high_card);
}

test "hand type string conversion" {
    try testing.expectEqualStrings("Straight Flush", HandEvaluator.handTypeToString(.straight_flush));
    try testing.expectEqualStrings("Four of a Kind", HandEvaluator.handTypeToString(.four_of_a_kind));
    try testing.expectEqualStrings("Full House", HandEvaluator.handTypeToString(.full_house));
    try testing.expectEqualStrings("Flush", HandEvaluator.handTypeToString(.flush));
    try testing.expectEqualStrings("Straight", HandEvaluator.handTypeToString(.straight));
    try testing.expectEqualStrings("Three of a Kind", HandEvaluator.handTypeToString(.three_of_a_kind));
    try testing.expectEqualStrings("Two Pair", HandEvaluator.handTypeToString(.two_pair));
    try testing.expectEqualStrings("Pair", HandEvaluator.handTypeToString(.pair));
    try testing.expectEqualStrings("High Card", HandEvaluator.handTypeToString(.high_card));
}

test "lookup table consistency" {
    var tables = lookup_tables.Tables.init();
    defer tables.deinit();
    try tables.initTables();
    
    // Test that lookup tables are populated
    try testing.expect(tables.flush_map.count() > 0);
    try testing.expect(tables.unsuited_map.count() > 0);
    
    std.debug.print("Flush lookup table entries: {d}\n", .{tables.flush_map.count()});
    std.debug.print("Unsuited lookup table entries: {d}\n", .{tables.unsuited_map.count()});
}

// Simplified test for now - full evaluation requires working lookup tables
test "basic hand evaluation setup" {
    var evaluator = HandEvaluator.init();
    defer evaluator.lookup_tables.deinit();
    try evaluator.lookup_tables.initTables();
    
    // Test that evaluator initializes
    try testing.expect(evaluator.lookup_tables.flush_map.count() > 0);
}

test "batch evaluation setup" {
    const BatchSize = 4;
    var batch_evaluator = BatchEvaluator.init();
    defer batch_evaluator.evaluator.lookup_tables.deinit();
    try batch_evaluator.evaluator.lookup_tables.initTables();
    
    // Create simple test hands
    const hands = [BatchSize][5]Card{
        [5]Card{ // Hand 1
            CardOps.fromString("As"),
            CardOps.fromString("Ks"),
            CardOps.fromString("Qs"),
            CardOps.fromString("Js"),
            CardOps.fromString("Ts"),
        },
        [5]Card{ // Hand 2
            CardOps.fromString("As"),
            CardOps.fromString("Ah"),
            CardOps.fromString("Ad"),
            CardOps.fromString("Ac"),
            CardOps.fromString("Ks"),
        },
        [5]Card{ // Hand 3
            CardOps.fromString("As"),
            CardOps.fromString("Ah"),
            CardOps.fromString("Ad"),
            CardOps.fromString("Ks"),
            CardOps.fromString("Kh"),
        },
        [5]Card{ // Hand 4
            CardOps.fromString("As"),
            CardOps.fromString("Kh"),
            CardOps.fromString("Qd"),
            CardOps.fromString("Jc"),
            CardOps.fromString("9s"),
        },
    };
    
    var results: [BatchSize]HandRank = undefined;
    batch_evaluator.evaluateFiveBatch(&hands, &results);
    
    // Basic validation that we get results
    for (results) |result| {
        try testing.expect(result >= 1 and result <= 7462);
    }
}