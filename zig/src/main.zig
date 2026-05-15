// Poker AI Library - Main Interface
// High-performance poker AI system with MCCFR algorithm implementation

const std = @import("std");
pub const config = @import("config.zig");

// Core modules
pub const hand_eval = @import("hand_eval.zig");
pub const lookup_tables = @import("lookup_tables.zig");
pub const game_state = @import("game_state.zig");
pub const cfr = @import("cfr.zig");
pub const strategy_table = @import("strategy_table.zig");
pub const parallel_cfr = @import("parallel_cfr.zig");
pub const utils = @import("utils.zig");
pub const clustering = @import("clustering.zig");

// MCCFR modules
pub const mccfr = @import("mccfr.zig");
pub const linear_cfr = @import("linear_cfr.zig");
pub const game_tree = @import("game_tree.zig");
pub const info_set = @import("info_set.zig");
pub const regret_table = @import("regret_table.zig");
pub const strategy_aggregator = @import("strategy_aggregator.zig");
pub const monte_carlo_sampler = @import("monte_carlo_sampler.zig");

// New Texas Hold'em game engine modules
pub const game_engine = @import("game_engine.zig");
pub const player = @import("player.zig");
pub const pot = @import("pot.zig");
pub const betting = @import("betting.zig");
pub const action_validator = @import("action_validator.zig");

// Tournament system modules
pub const tournament = @import("tournament.zig");
pub const tournament_parallel = @import("tournament_parallel.zig");

// Terminal UI modules
pub const terminal_ui = @import("terminal_ui.zig");
pub const cli_parser = @import("cli_parser.zig");
pub const ascii_cards = @import("ascii_cards.zig");
pub const game_display = @import("game_display.zig");
pub const input_handler = @import("input_handler.zig");

// C API for Python FFI
pub const c_api = @import("c_api.zig");

// Library version information
pub const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

// Global allocator interface - must be set before using the library
var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
var allocator_is_default = true;
pub var allocator: std.mem.Allocator = gpa_instance.allocator();

/// Initialize the poker AI library with a custom allocator
pub fn init(alloc: std.mem.Allocator) void {
    allocator_is_default = false;
    allocator = alloc;
}

/// Deinitialize the library and clean up resources
pub fn deinit() void {
    if (allocator_is_default) {
        _ = gpa_instance.deinit();
    }
    allocator = gpa_instance.allocator();
    allocator_is_default = true;
}

// Export key types and constants
pub const Card = game_state.Card;
pub const Hand = game_state.Hand;
pub const GameState = game_state.GameState;
pub const Action = game_state.Action;
pub const HandRank = hand_eval.HandRank;
pub const StrategyProfile = strategy_table.StrategyProfile;

// Key constants - imported from central config
pub const MAX_PLAYERS = config.MAX_PLAYERS;
pub const MIN_PLAYERS = config.MIN_PLAYERS;
pub const DEFAULT_PLAYERS = config.DEFAULT_PLAYERS;
pub const DECK_SIZE = config.DECK_SIZE;
pub const HAND_SIZE = config.HOLE_CARDS;
pub const BOARD_SIZE = config.MAX_BOARD_CARDS;

// Error types
pub const PokerError = error{
    InvalidCard,
    InvalidAction,
    GameStateError,
    AllocationError,
    LookupTableError,
    StrategyError,
};

test "library initialization" {
    const testing = std.testing;

    // Test basic initialization
    init(testing.allocator);
    defer deinit();

    // Verify allocator can allocate
    const buffer = try allocator.alloc(u8, 1);
    allocator.free(buffer);
}

test "version check" {
    const testing = std.testing;

    try testing.expect(version.major == 0);
    try testing.expect(version.minor == 1);
    try testing.expect(version.patch == 0);
}
