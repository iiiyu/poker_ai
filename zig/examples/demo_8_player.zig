//! Demonstration of 8-player poker game
//! Shows that the system now supports up to 8 players

const std = @import("std");
const poker_ai = @import("poker_ai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== 8-Player Poker Game Demo ===\n\n", .{});
    
    // Show configuration
    std.debug.print("System Configuration:\n", .{});
    std.debug.print("  MAX_PLAYERS: {d}\n", .{poker_ai.config.MAX_PLAYERS});
    std.debug.print("  MIN_PLAYERS: {d}\n", .{poker_ai.config.MIN_PLAYERS});
    std.debug.print("  DEFAULT_PLAYERS: {d}\n\n", .{poker_ai.config.DEFAULT_PLAYERS});

    // Initialize 8-player game
    const game_config = poker_ai.game_engine.GameConfig{
        .small_blind = 25,
        .big_blind = 50,
        .initial_stack = 2000,
    };
    
    var engine = try poker_ai.game_engine.TexasHoldemGameEngine.init(allocator, 8, game_config);
    defer engine.deinit();
    
    std.debug.print("Game initialized with {d} players!\n\n", .{engine.num_players});
    
    // Show all players
    std.debug.print("Player Setup:\n", .{});
    for (0..8) |i| {
        const p = engine.players[i];
        std.debug.print("  Player {d}: Stack=${d}, Active={}\n", .{ 
            p.id, 
            p.stack, 
            p.is_active 
        });
    }
    
    // Deal cards to demonstrate 8-player dealing
    std.debug.print("\nDealing cards to 8 players...\n", .{});
    
    // Simulate dealing (normally done through game flow)
    const hole_cards = [_][2]u8{
        .{ 0, 13 },  // A♠ A♣
        .{ 12, 25 }, // K♠ K♣  
        .{ 11, 24 }, // Q♠ Q♣
        .{ 10, 23 }, // J♠ J♣
        .{ 9, 22 },  // T♠ T♣
        .{ 8, 21 },  // 9♠ 9♣
        .{ 7, 20 },  // 8♠ 8♣
        .{ 6, 19 },  // 7♠ 7♣
    };
    
    for (0..8) |i| {
        engine.players[i].hole_cards = hole_cards[i];
        engine.players[i].has_cards = true;
        std.debug.print("  Player {d}: {s}{s}\n", .{
            i,
            cardToString(hole_cards[i][0]),
            cardToString(hole_cards[i][1]),
        });
    }
    
    // Show pot manager can handle 8 players
    std.debug.print("\nPot Management for 8 players:\n", .{});
    
    // Everyone calls big blind
    for (0..8) |i| {
        try engine.pot_manager.addToPot(50, @intCast(i));
    }
    
    std.debug.print("  Total pot after all players call: ${d}\n", .{
        engine.pot_manager.getTotalPot()
    });
    
    // Demonstrate betting tracking for 8 players
    std.debug.print("\nSimulated Betting Round with 8 players:\n", .{});
    
    // Show some example actions  
    const actions = [_]struct { player: u8, action: []const u8, amount: u32 }{
        .{ .player = 0, .action = "call", .amount = 50 },
        .{ .player = 1, .action = "raise", .amount = 150 },
        .{ .player = 2, .action = "fold", .amount = 0 },
        .{ .player = 3, .action = "call", .amount = 150 },
        .{ .player = 4, .action = "fold", .amount = 0 },
        .{ .player = 5, .action = "call", .amount = 150 },
        .{ .player = 6, .action = "all-in", .amount = 2000 },
        .{ .player = 7, .action = "fold", .amount = 0 },
    };
    
    for (actions) |act| {
        std.debug.print("  Player {d} {s}", .{ act.player, act.action });
        if (act.amount > 0) {
            std.debug.print(" ${d}", .{act.amount});
        }
        std.debug.print("\n", .{});
    }
    
    std.debug.print("  Active players remaining: 5 out of 8\n", .{});
    
    // Show MCCFR configuration for 8 players
    std.debug.print("\nMCCFR Training Configuration for 8 players:\n", .{});
    const mccfr_config = poker_ai.config.getMCCFRConfig(8);
    std.debug.print("  Iterations: {d}\n", .{mccfr_config.iterations});
    std.debug.print("  Batch size: {d}\n", .{mccfr_config.batch_size});
    std.debug.print("  Exploration ε: {d:.2}\n", .{mccfr_config.exploration_epsilon});
    std.debug.print("  Pruning threshold: {d:.0}\n", .{mccfr_config.pruning_threshold});
    
    // Memory estimates
    std.debug.print("\nMemory Estimates for 8-player MCCFR:\n", .{});
    const mem_config = poker_ai.config.MemoryConfig{};
    const estimated_memory = @as(f32, @floatFromInt(mem_config.base_memory_6p)) * mem_config.memory_multiplier_8p;
    std.debug.print("  Base (6 players): {d:.1} GB\n", .{
        @as(f32, @floatFromInt(mem_config.base_memory_6p)) / (1024 * 1024 * 1024)
    });
    std.debug.print("  Estimated (8 players): {d:.1} GB\n", .{
        estimated_memory / (1024 * 1024 * 1024)
    });
    std.debug.print("  Maximum allowed: {d:.1} GB\n", .{
        @as(f32, @floatFromInt(mem_config.max_training_memory)) / (1024 * 1024 * 1024)
    });
    
    // Terminal display recommendations
    std.debug.print("\nTerminal Display Recommendations:\n", .{});
    std.debug.print("  Recommended width for 6 players: {d} chars\n", .{
        poker_ai.config.getRecommendedTerminalWidth(6)
    });
    std.debug.print("  Recommended width for 8 players: {d} chars\n", .{
        poker_ai.config.getRecommendedTerminalWidth(8)
    });
    
    std.debug.print("\n✅ 8-player support successfully demonstrated!\n\n", .{});
}

fn cardToString(card: u8) []const u8 {
    if (card >= 52) return "??";
    
    // This is simplified - in real code we'd build a proper string
    return switch (card) {
        0 => "A♠", 13 => "A♣", 26 => "A♦", 39 => "A♥",
        12 => "K♠", 25 => "K♣", 38 => "K♦", 51 => "K♥",
        11 => "Q♠", 24 => "Q♣", 37 => "Q♦", 50 => "Q♥",
        10 => "J♠", 23 => "J♣", 36 => "J♦", 49 => "J♥",
        9 => "T♠", 22 => "T♣", 35 => "T♦", 48 => "T♥",
        8 => "9♠", 21 => "9♣", 34 => "9♦", 47 => "9♥",
        7 => "8♠", 20 => "8♣", 33 => "8♦", 46 => "8♥",
        6 => "7♠", 19 => "7♣", 32 => "7♦", 45 => "7♥",
        else => "??",
    };
}