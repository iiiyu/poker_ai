//! Tournament Simulation System
//!
//! High-performance tournament system for poker AI evaluation and comparison
//! Supports multiple tournament formats, blind progression, and parallel execution
//!
//! Features:
//! - Cash games, freezeout tournaments, and Sit-N-Go formats
//! - Blind level progression with configurable schedules
//! - Player elimination tracking and payouts
//! - Statistics collection (win rate, chips, hands played)
//! - ELO rating system for AI agent comparison
//! - Game history logging for analysis
//! - Parallel tournament execution

const std = @import("std");
const game_engine = @import("game_engine.zig");
const player = @import("player.zig");
const strategy_table = @import("strategy_table.zig");
const hand_eval = @import("hand_eval.zig");

pub const PlayerId = game_engine.PlayerId;
pub const ChipAmount = game_engine.ChipAmount;
pub const Card = game_engine.Card;

/// Tournament format types
pub const TournamentFormat = enum(u8) {
    cash_game, // Fixed blinds, unlimited rebuys
    freezeout, // Elimination tournament with increasing blinds
    sit_n_go, // Single table tournament
    multi_table, // Multi-table tournament
    heads_up, // One-on-one tournament

    pub fn toString(self: TournamentFormat) []const u8 {
        return switch (self) {
            .cash_game => "cash_game",
            .freezeout => "freezeout",
            .sit_n_go => "sit_n_go",
            .multi_table => "multi_table",
            .heads_up => "heads_up",
        };
    }
};

/// Blind level structure
pub const BlindLevel = struct {
    small_blind: ChipAmount,
    big_blind: ChipAmount,
    ante: ChipAmount,
    duration_hands: u32, // Number of hands at this level

    pub fn init(small_blind: ChipAmount, big_blind: ChipAmount, ante: ChipAmount, duration_hands: u32) BlindLevel {
        return BlindLevel{
            .small_blind = small_blind,
            .big_blind = big_blind,
            .ante = ante,
            .duration_hands = duration_hands,
        };
    }
};

/// Blind schedule for tournament progression
pub const BlindSchedule = struct {
    levels: []const BlindLevel,
    current_level: u32,
    hands_at_current_level: u32,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, levels: []const BlindLevel) !Self {
        const owned_levels = try allocator.dupe(BlindLevel, levels);
        return Self{
            .levels = owned_levels,
            .current_level = 0,
            .hands_at_current_level = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.levels);
    }

    pub fn getCurrentBlinds(self: Self) BlindLevel {
        if (self.current_level >= self.levels.len) {
            // Use last level if exceeded
            return self.levels[self.levels.len - 1];
        }
        return self.levels[self.current_level];
    }

    pub fn advanceHand(self: *Self) void {
        self.hands_at_current_level += 1;

        if (self.current_level < self.levels.len) {
            const current_blinds = self.levels[self.current_level];
            if (self.hands_at_current_level >= current_blinds.duration_hands) {
                self.current_level += 1;
                self.hands_at_current_level = 0;
            }
        }
    }

    pub fn shouldAdvanceLevel(self: Self) bool {
        if (self.current_level >= self.levels.len) return false;
        const current_blinds = self.levels[self.current_level];
        return self.hands_at_current_level >= current_blinds.duration_hands;
    }
};

/// Player tournament statistics
pub const PlayerStats = struct {
    player_id: PlayerId,
    hands_played: u32,
    hands_won: u32,
    chips_won: i64, // Can be negative
    initial_stack: ChipAmount,
    final_stack: ChipAmount,
    elimination_position: ?u32, // null if still active
    elo_rating: f64,
    elo_rating_change: f64,

    pub fn init(player_id: PlayerId, initial_stack: ChipAmount, elo_rating: f64) PlayerStats {
        return PlayerStats{
            .player_id = player_id,
            .hands_played = 0,
            .hands_won = 0,
            .chips_won = 0,
            .initial_stack = initial_stack,
            .final_stack = initial_stack,
            .elimination_position = null,
            .elo_rating = elo_rating,
            .elo_rating_change = 0.0,
        };
    }

    pub fn updateHandResult(self: *PlayerStats, chips_change: i64, won_hand: bool) void {
        self.hands_played += 1;
        if (won_hand) {
            self.hands_won += 1;
        }
        self.chips_won += chips_change;

        // Update final stack (assuming it tracks current stack)
        if (chips_change > 0) {
            self.final_stack += @intCast(chips_change);
        } else {
            const loss: ChipAmount = @intCast(-chips_change);
            if (loss >= self.final_stack) {
                self.final_stack = 0;
            } else {
                self.final_stack -= loss;
            }
        }
    }

    pub fn getWinRate(self: PlayerStats) f64 {
        if (self.hands_played == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hands_won)) / @as(f64, @floatFromInt(self.hands_played));
    }

    pub fn getROI(self: PlayerStats) f64 {
        if (self.initial_stack == 0) return 0.0;
        return @as(f64, @floatFromInt(self.chips_won)) / @as(f64, @floatFromInt(self.initial_stack));
    }
};

/// Game history record for a single hand
pub const HandRecord = struct {
    hand_number: u32,
    blind_level: BlindLevel,
    active_players: []PlayerId,
    winner_id: ?PlayerId,
    pot_size: ChipAmount,
    board_cards: [5]Card, // All community cards (may be empty for early folds)
    showdown_occurred: bool,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        hand_number: u32,
        blind_level: BlindLevel,
        active_players: []const PlayerId,
    ) !Self {
        const owned_players = try allocator.dupe(PlayerId, active_players);
        return Self{
            .hand_number = hand_number,
            .blind_level = blind_level,
            .active_players = owned_players,
            .winner_id = null,
            .pot_size = 0,
            .board_cards = [_]Card{255} ** 5, // Invalid card marker
            .showdown_occurred = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.active_players);
    }

    pub fn finalize(self: *Self, winner_id: PlayerId, pot_size: ChipAmount, board: []const Card, showdown: bool) void {
        self.winner_id = winner_id;
        self.pot_size = pot_size;
        self.showdown_occurred = showdown;

        // Copy board cards
        for (board, 0..) |card, i| {
            if (i < self.board_cards.len) {
                self.board_cards[i] = card;
            }
        }
    }
};

/// Payout structure for tournaments
pub const PayoutStructure = struct {
    positions: []const u32, // Finishing positions that get paid
    percentages: []const f64, // Percentage of prize pool for each position
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, positions: []const u32, percentages: []const f64) !Self {
        if (positions.len != percentages.len) {
            return error.MismatchedPayoutArrays;
        }

        const owned_positions = try allocator.dupe(u32, positions);
        const owned_percentages = try allocator.dupe(f64, percentages);

        return Self{
            .positions = owned_positions,
            .percentages = owned_percentages,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.positions);
        self.allocator.free(self.percentages);
    }

    pub fn getPayoutForPosition(self: Self, position: u32, total_prize_pool: ChipAmount) ChipAmount {
        for (self.positions, 0..) |pos, i| {
            if (pos == position) {
                const payout_f64 = @as(f64, @floatFromInt(total_prize_pool)) * self.percentages[i];
                return @intFromFloat(payout_f64);
            }
        }
        return 0;
    }
};

/// ELO rating calculation utilities
pub const ELOCalculator = struct {
    const K_FACTOR: f64 = 32.0; // Standard ELO K-factor

    pub fn calculateExpectedScore(rating_a: f64, rating_b: f64) f64 {
        const diff = rating_b - rating_a;
        return 1.0 / (1.0 + std.math.pow(f64, 10.0, diff / 400.0));
    }

    pub fn updateRating(current_rating: f64, expected_score: f64, actual_score: f64) f64 {
        return current_rating + K_FACTOR * (actual_score - expected_score);
    }

    pub fn calculateRatingChanges(player_ratings: []f64, results: []f64) void {
        const n = player_ratings.len;
        var new_ratings = try std.ArrayList(f64).initCapacity(std.heap.page_allocator, 0);
        defer new_ratings.deinit();

        new_ratings.appendSlice(player_ratings) catch return;

        for (0..n) |i| {
            var expected_total: f64 = 0.0;
            const actual_total: f64 = results[i];

            // Calculate expected score against all opponents
            for (0..n) |j| {
                if (i != j) {
                    expected_total += calculateExpectedScore(player_ratings[i], player_ratings[j]);
                }
            }

            // Normalize expected score
            if (n > 1) {
                expected_total /= @as(f64, @floatFromInt(n - 1));
            }

            // Update rating
            new_ratings.items[i] = updateRating(player_ratings[i], expected_total, actual_total);
        }

        // Copy back new ratings
        @memcpy(player_ratings, new_ratings.items);
    }
};

/// Main tournament structure
pub const Tournament = struct {
    // Configuration
    format: TournamentFormat,
    max_players: u8,
    initial_stack: ChipAmount,
    blind_schedule: BlindSchedule,
    payout_structure: ?PayoutStructure,

    // State
    players: std.ArrayList(player.Player),
    eliminated_players: std.ArrayList(PlayerId),
    current_hand: u32,
    total_prize_pool: ChipAmount,

    // Statistics and history
    player_stats: std.HashMap(PlayerId, PlayerStats, std.hash_map.AutoContext(PlayerId), 80),
    hand_history: std.ArrayList(HandRecord),

    // Utilities
    allocator: std.mem.Allocator,
    rng: std.Random,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        format: TournamentFormat,
        max_players: u8,
        initial_stack: ChipAmount,
        blind_levels: []const BlindLevel,
        rng: std.Random,
    ) !Self {
        var tournament = Self{
            .format = format,
            .max_players = max_players,
            .initial_stack = initial_stack,
            .blind_schedule = try BlindSchedule.init(allocator, blind_levels),
            .payout_structure = null,
            .players = try std.ArrayList(player.Player).initCapacity(allocator, 0),
            .eliminated_players = try std.ArrayList(PlayerId).initCapacity(allocator, 0),
            .current_hand = 0,
            .total_prize_pool = 0,
            .player_stats = std.HashMap(PlayerId, PlayerStats, std.hash_map.AutoContext(PlayerId), 80).init(allocator),
            .hand_history = try std.ArrayList(HandRecord).initCapacity(allocator, 0),
            .allocator = allocator,
            .rng = rng,
        };

        try tournament.players.ensureTotalCapacity(allocator, max_players);
        return tournament;
    }

    pub fn deinit(self: *Self) void {
        self.blind_schedule.deinit();
        if (self.payout_structure) |*payout| {
            payout.deinit();
        }
        self.players.deinit(self.allocator);
        self.eliminated_players.deinit(self.allocator);
        self.player_stats.deinit();

        // Clean up hand history
        for (self.hand_history.items) |*record| {
            record.deinit();
        }
        self.hand_history.deinit(self.allocator);
    }

    /// Add a player to the tournament
    pub fn addPlayer(self: *Self, player_id: PlayerId, elo_rating: f64) !void {
        if (self.players.items.len >= self.max_players) {
            return error.TournamentFull;
        }

        const new_player = player.Player.init(player_id, self.initial_stack);
        try self.players.append(self.allocator, new_player);

        const stats = PlayerStats.init(player_id, self.initial_stack, elo_rating);
        try self.player_stats.put(player_id, stats);

        self.total_prize_pool += self.initial_stack;
    }

    /// Set payout structure for tournament
    pub fn setPayoutStructure(self: *Self, positions: []const u32, percentages: []const f64) !void {
        self.payout_structure = try PayoutStructure.init(self.allocator, positions, percentages);
    }

    /// Check if tournament is complete
    pub fn isComplete(self: Self) bool {
        return switch (self.format) {
            .cash_game => false, // Cash games don't end automatically
            .heads_up => self.getActivePlayers().len <= 1,
            else => self.getActivePlayers().len <= 1,
        };
    }

    /// Get list of active (non-eliminated) players
    pub fn getActivePlayers(self: Self) []const player.Player {
        // Filter for active players
        var active_count: usize = 0;
        for (self.players.items) |p| {
            if (p.is_active and p.stack > 0) {
                active_count += 1;
            }
        }

        // This is a simplified implementation
        // In practice, you'd want to maintain a separate active players list
        return self.players.items[0..active_count];
    }

    /// Advance to next hand
    pub fn advanceHand(self: *Self) void {
        self.current_hand += 1;
        self.blind_schedule.advanceHand();

        // Handle blind level changes
        if (self.blind_schedule.shouldAdvanceLevel()) {
            // Log blind level advancement if needed
        }
    }

    /// Run a single hand of the tournament
    pub fn runHand(self: *Self, game: *game_engine.GameEngine) !void {
        const active_players = self.getActivePlayers();
        if (active_players.len < 2) {
            return; // Not enough players to continue
        }

        // Create hand record
        var active_player_ids = try self.allocator.alloc(PlayerId, active_players.len);
        defer self.allocator.free(active_player_ids);

        for (active_players, 0..) |p, i| {
            active_player_ids[i] = p.id;
        }

        var hand_record = try HandRecord.init(
            self.allocator,
            self.current_hand,
            self.blind_schedule.getCurrentBlinds(),
            active_player_ids,
        );

        // Set up game with current blinds
        const blinds = self.blind_schedule.getCurrentBlinds();
        game.setBlinds(blinds.small_blind, blinds.big_blind, blinds.ante);

        // Play the hand (simplified - in practice this would involve the full game engine)
        // This would call the game engine to play out the hand
        // const hand_result = try game.playHand(active_players);

        // For now, simulate a simple result
        const winner_id = active_players[0].id; // Simplified
        const pot_size = blinds.small_blind + blinds.big_blind; // Simplified

        hand_record.finalize(winner_id, pot_size, &[_]Card{}, false);
        try self.hand_history.append(self.allocator, hand_record);

        // Update statistics
        self.updatePlayerStatistics(winner_id, pot_size);
        self.advanceHand();
    }

    /// Update player statistics after a hand
    fn updatePlayerStatistics(self: *Self, winner_id: PlayerId, pot_size: ChipAmount) void {
        var stats_iter = self.player_stats.iterator();
        while (stats_iter.next()) |entry| {
            const player_id = entry.key_ptr.*;
            const stats = entry.value_ptr;

            const won_hand = (player_id == winner_id);
            const chips_change: i64 = if (won_hand) @as(i64, @intCast(pot_size)) else 0;

            stats.updateHandResult(chips_change, won_hand);
        }
    }

    /// Calculate final payouts and update ELO ratings
    pub fn finalizeTournament(self: *Self) !void {
        if (!self.isComplete()) {
            return error.TournamentNotComplete;
        }

        // Calculate payouts if payout structure exists
        if (self.payout_structure) |payout| {
            var position: u32 = 1;

            // Award payouts based on finishing position
            for (self.eliminated_players.items) |player_id| {
                const payout_amount = payout.getPayoutForPosition(position, self.total_prize_pool);

                if (self.player_stats.getPtr(player_id)) |stats| {
                    stats.chips_won += @as(i64, @intCast(payout_amount));
                    stats.elimination_position = position;
                }

                position += 1;
            }
        }

        // Update ELO ratings
        try self.updateELORatings();
    }

    /// Update ELO ratings based on tournament results
    fn updateELORatings(self: *Self) !void {
        const player_count = self.player_stats.count();
        var ratings = try self.allocator.alloc(f64, player_count);
        defer self.allocator.free(ratings);

        var results = try self.allocator.alloc(f64, player_count);
        defer self.allocator.free(results);

        var i: usize = 0;
        var stats_iter = self.player_stats.iterator();
        while (stats_iter.next()) |entry| {
            const stats = entry.value_ptr;
            ratings[i] = stats.elo_rating;
            results[i] = stats.getROI(); // Use ROI as performance metric
            i += 1;
        }

        // Calculate new ratings
        ELOCalculator.calculateRatingChanges(ratings, results);

        // Update player stats with new ratings
        i = 0;
        stats_iter = self.player_stats.iterator();
        while (stats_iter.next()) |entry| {
            const stats = entry.value_ptr;
            stats.elo_rating_change = ratings[i] - stats.elo_rating;
            stats.elo_rating = ratings[i];
            i += 1;
        }
    }

    /// Get tournament summary statistics
    pub fn getTournamentSummary(self: Self) TournamentSummary {
        return TournamentSummary{
            .format = self.format,
            .total_hands = self.current_hand,
            .total_players = @intCast(self.player_stats.count()),
            .total_prize_pool = self.total_prize_pool,
            .is_complete = self.isComplete(),
        };
    }
};

/// Tournament summary statistics
pub const TournamentSummary = struct {
    format: TournamentFormat,
    total_hands: u32,
    total_players: u32,
    total_prize_pool: ChipAmount,
    is_complete: bool,
};

/// Default blind schedules for common tournament types
pub const DefaultBlindSchedules = struct {
    /// Standard Sit-N-Go blind schedule
    pub fn standardSNG(allocator: std.mem.Allocator) !BlindSchedule {
        const levels = [_]BlindLevel{
            BlindLevel.init(10, 20, 0, 20),
            BlindLevel.init(15, 30, 0, 20),
            BlindLevel.init(25, 50, 0, 20),
            BlindLevel.init(50, 100, 0, 20),
            BlindLevel.init(75, 150, 0, 20),
            BlindLevel.init(100, 200, 25, 20),
            BlindLevel.init(150, 300, 50, 20),
            BlindLevel.init(200, 400, 75, 20),
            BlindLevel.init(300, 600, 100, 20),
            BlindLevel.init(500, 1000, 150, 20),
        };
        return BlindSchedule.init(allocator, &levels);
    }

    /// Cash game (fixed blinds)
    pub fn cashGame(allocator: std.mem.Allocator, small_blind: ChipAmount, big_blind: ChipAmount) !BlindSchedule {
        const levels = [_]BlindLevel{
            BlindLevel.init(small_blind, big_blind, 0, std.math.maxInt(u32)),
        };
        return BlindSchedule.init(allocator, &levels);
    }

    /// Heads-up tournament schedule
    pub fn headsUp(allocator: std.mem.Allocator) !BlindSchedule {
        const levels = [_]BlindLevel{
            BlindLevel.init(5, 10, 0, 10),
            BlindLevel.init(10, 20, 0, 10),
            BlindLevel.init(15, 30, 0, 10),
            BlindLevel.init(25, 50, 0, 10),
            BlindLevel.init(50, 100, 0, 10),
            BlindLevel.init(100, 200, 0, 10),
            BlindLevel.init(200, 400, 0, 10),
            BlindLevel.init(500, 1000, 0, 10),
        };
        return BlindSchedule.init(allocator, &levels);
    }
};
