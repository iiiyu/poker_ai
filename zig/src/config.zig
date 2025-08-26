//! Central configuration for poker AI system
//! 
//! This module defines all system-wide constants to ensure consistency
//! across the codebase. All player limits and game parameters should
//! be defined here and imported by other modules.

const std = @import("std");

/// Maximum number of players supported in a game
pub const MAX_PLAYERS: u8 = 8;

/// Minimum number of players required for a game
pub const MIN_PLAYERS: u8 = 2;

/// Default number of players for new games
pub const DEFAULT_PLAYERS: u8 = 6;

/// Maximum cards in a standard deck
pub const DECK_SIZE: u8 = 52;

/// Number of hole cards per player
pub const HOLE_CARDS: u8 = 2;

/// Maximum community cards on board
pub const MAX_BOARD_CARDS: u8 = 5;

/// Memory configuration for MCCFR training
pub const MemoryConfig = struct {
    /// Base memory allocation for 6-player games (bytes)
    base_memory_6p: usize = 2 * 1024 * 1024 * 1024, // 2GB
    
    /// Memory multiplier for 8-player games
    memory_multiplier_8p: f32 = 2.5,
    
    /// Maximum memory allowed for training (bytes)
    max_training_memory: usize = 8 * 1024 * 1024 * 1024, // 8GB
};

/// MCCFR configuration adjustments based on player count
pub fn getMCCFRConfig(player_count: u8) struct {
    iterations: u32,
    batch_size: u32,
    exploration_epsilon: f32,
    pruning_threshold: f32,
} {
    return switch (player_count) {
        2...4 => .{
            .iterations = 50000,
            .batch_size = 100,
            .exploration_epsilon = 0.6,
            .pruning_threshold = -300.0,
        },
        5...6 => .{
            .iterations = 100000,
            .batch_size = 150,
            .exploration_epsilon = 0.55,
            .pruning_threshold = -400.0,
        },
        7...8 => .{
            .iterations = 200000,
            .batch_size = 250,
            .exploration_epsilon = 0.5,
            .pruning_threshold = -500.0,
        },
        else => .{
            .iterations = 100000,
            .batch_size = 150,
            .exploration_epsilon = 0.6,
            .pruning_threshold = -300.0,
        },
    };
}

/// Get recommended terminal width for player count
pub fn getRecommendedTerminalWidth(player_count: u8) u16 {
    return switch (player_count) {
        2...4 => 100,
        5...6 => 120,
        7...8 => 140,
        else => 120,
    };
}

test "config player limits" {
    const testing = std.testing;
    
    try testing.expect(MAX_PLAYERS >= MIN_PLAYERS);
    try testing.expect(DEFAULT_PLAYERS >= MIN_PLAYERS);
    try testing.expect(DEFAULT_PLAYERS <= MAX_PLAYERS);
    try testing.expectEqual(@as(u8, 8), MAX_PLAYERS);
}

test "MCCFR config scaling" {
    const testing = std.testing;
    
    const config_6p = getMCCFRConfig(6);
    const config_8p = getMCCFRConfig(8);
    
    // Verify scaling
    try testing.expect(config_8p.iterations > config_6p.iterations);
    try testing.expect(config_8p.batch_size > config_6p.batch_size);
    try testing.expect(config_8p.exploration_epsilon <= config_6p.exploration_epsilon);
}