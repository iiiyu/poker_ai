const std = @import("std");
const testing = std.testing;
const simple = @import("simple");

test "simple hand evaluator basic tests" {
    // Test compile-time card creation using constants
    comptime {
        const ace_spades = simple.CardOps.fromString("As");
        if (simple.CardOps.getRank(ace_spades) != 12) @compileError("Ace rank should be 12");
        if (simple.CardOps.getSuit(ace_spades) != simple.SUIT_SPADES) @compileError("Ace of spades suit incorrect");
        if (simple.CardOps.getPrime(ace_spades) != 41) @compileError("Ace prime should be 41");
    }
    
    // Test runtime card creation
    const runtime_ace = try simple.CardOps.fromStringRuntime("As");
    const comptime_ace = comptime simple.CardOps.fromString("As");
    try testing.expect(runtime_ace == comptime_ace);
    
    // Test hand type classification
    try testing.expect(simple.getHandType(1) == .straight_flush);
    try testing.expect(simple.getHandType(7462) == .high_card);
    
    // Test string conversion
    try testing.expectEqualStrings("Straight Flush", simple.handTypeToString(.straight_flush));
    try testing.expectEqualStrings("High Card", simple.handTypeToString(.high_card));
}