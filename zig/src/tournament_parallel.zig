//! Parallel Tournament Execution System
//!
//! High-performance parallel tournament execution for rapid AI evaluation
//! Enables running multiple tournaments concurrently for statistical significance
//!
//! Features:
//! - Thread-safe tournament execution
//! - Configurable worker thread pool
//! - Result aggregation across multiple tournaments
//! - Load balancing for optimal CPU utilization
//! - Memory-efficient batch processing

const std = @import("std");
const tournament_mod = @import("tournament.zig");
const game_engine = @import("game_engine.zig");
const strategy_table = @import("strategy_table.zig");

const Tournament = tournament_mod.Tournament;
const TournamentFormat = tournament_mod.TournamentFormat;
const BlindLevel = tournament_mod.BlindLevel;
const PlayerStats = tournament_mod.PlayerStats;
const TournamentSummary = tournament_mod.TournamentSummary;

/// Configuration for parallel tournament execution
pub const ParallelTournamentConfig = struct {
    // Tournament settings
    format: TournamentFormat,
    max_players: u8,
    initial_stack: u32,
    blind_levels: []const BlindLevel,
    payout_positions: []const u32,
    payout_percentages: []const f64,

    // Parallel execution settings
    num_tournaments: u32,
    num_worker_threads: u32,
    batch_size: u32, // Tournaments per batch

    // Player configuration
    player_ids: []const u8,
    initial_elo_ratings: []const f64,

    // Results collection
    collect_detailed_stats: bool,
    collect_hand_history: bool,

    pub fn validate(self: ParallelTournamentConfig) !void {
        if (self.max_players < 2 or self.max_players > 10) {
            return error.InvalidPlayerCount;
        }

        if (self.num_tournaments == 0) {
            return error.InvalidTournamentCount;
        }

        if (self.num_worker_threads == 0 or self.num_worker_threads > 16) {
            return error.InvalidThreadCount;
        }

        if (self.player_ids.len != self.initial_elo_ratings.len) {
            return error.MismatchedPlayerData;
        }

        if (self.player_ids.len > self.max_players) {
            return error.TooManyPlayers;
        }

        if (self.payout_positions.len != self.payout_percentages.len) {
            return error.MismatchedPayoutData;
        }
    }
};

/// Results from a single tournament
pub const TournamentResult = struct {
    tournament_id: u32,
    summary: TournamentSummary,
    player_stats: std.HashMap(u8, PlayerStats, std.hash_map.AutoContext(u8), 80),
    execution_time_ms: u64,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, tournament_id: u32) Self {
        return Self{
            .tournament_id = tournament_id,
            .summary = undefined,
            .player_stats = std.HashMap(u8, PlayerStats, std.hash_map.AutoContext(u8), 80).init(allocator),
            .execution_time_ms = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.player_stats.deinit();
    }
};

/// Aggregated results from multiple tournaments
pub const AggregatedResults = struct {
    total_tournaments: u32,
    successful_tournaments: u32,
    total_execution_time_ms: u64,

    // Per-player aggregated statistics
    player_aggregates: std.HashMap(u8, PlayerAggregate, std.hash_map.AutoContext(u8), 80),

    // Overall tournament statistics
    average_hands_per_tournament: f64,
    tournament_completion_rate: f64,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .total_tournaments = 0,
            .successful_tournaments = 0,
            .total_execution_time_ms = 0,
            .player_aggregates = std.HashMap(u8, PlayerAggregate, std.hash_map.AutoContext(u8), 80).init(allocator),
            .average_hands_per_tournament = 0.0,
            .tournament_completion_rate = 0.0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.player_aggregates.deinit();
    }

    pub fn addTournamentResult(self: *Self, result: *const TournamentResult) !void {
        self.total_tournaments += 1;

        if (result.summary.is_complete) {
            self.successful_tournaments += 1;
        }

        self.total_execution_time_ms += result.execution_time_ms;

        // Update player aggregates
        var stats_iter = result.player_stats.iterator();
        while (stats_iter.next()) |entry| {
            const player_id = entry.key_ptr.*;
            const stats = entry.value_ptr.*;

            var aggregate = self.player_aggregates.get(player_id) orelse PlayerAggregate.init(player_id);
            aggregate.addTournament(stats);
            try self.player_aggregates.put(player_id, aggregate);
        }

        // Update overall statistics
        self.updateOverallStats();
    }

    fn updateOverallStats(self: *Self) void {
        if (self.total_tournaments > 0) {
            self.tournament_completion_rate = @as(f64, @floatFromInt(self.successful_tournaments)) / @as(f64, @floatFromInt(self.total_tournaments));
        }
    }

    pub fn getPlayerRankings(self: Self, allocator: std.mem.Allocator) ![]PlayerAggregate {
        var rankings = std.ArrayList(PlayerAggregate).init(allocator);
        defer rankings.deinit();

        var iter = self.player_aggregates.valueIterator();
        while (iter.next()) |aggregate| {
            try rankings.append(aggregate.*);
        }

        // Sort by ELO rating
        const SortContext = struct {
            fn lessThan(context: void, a: PlayerAggregate, b: PlayerAggregate) bool {
                _ = context;
                return a.average_elo_rating > b.average_elo_rating;
            }
        };

        std.sort.insertion(PlayerAggregate, rankings.items, {}, SortContext.lessThan);

        return try rankings.toOwnedSlice();
    }
};

/// Aggregated statistics for a single player across multiple tournaments
pub const PlayerAggregate = struct {
    player_id: u8,
    tournaments_played: u32,
    total_hands_played: u32,
    total_hands_won: u32,
    total_chips_won: i64,

    // Averages
    average_win_rate: f64,
    average_roi: f64,
    average_elo_rating: f64,
    total_elo_change: f64,

    // Tournament placement statistics
    first_place_finishes: u32,
    in_the_money_finishes: u32,

    pub fn init(player_id: u8) PlayerAggregate {
        return PlayerAggregate{
            .player_id = player_id,
            .tournaments_played = 0,
            .total_hands_played = 0,
            .total_hands_won = 0,
            .total_chips_won = 0,
            .average_win_rate = 0.0,
            .average_roi = 0.0,
            .average_elo_rating = 1500.0, // Default ELO
            .total_elo_change = 0.0,
            .first_place_finishes = 0,
            .in_the_money_finishes = 0,
        };
    }

    pub fn addTournament(self: *PlayerAggregate, stats: PlayerStats) void {
        self.tournaments_played += 1;
        self.total_hands_played += stats.hands_played;
        self.total_hands_won += stats.hands_won;
        self.total_chips_won += stats.chips_won;
        self.total_elo_change += stats.elo_rating_change;

        // Check tournament placement
        if (stats.elimination_position) |position| {
            if (position == 1) {
                self.first_place_finishes += 1;
            }

            // Assuming ITM is top 20% (simplified)
            if (position <= 3) { // Top 3 for small tournaments
                self.in_the_money_finishes += 1;
            }
        }

        // Update averages
        self.updateAverages();
    }

    fn updateAverages(self: *PlayerAggregate) void {
        if (self.tournaments_played > 0) {
            self.average_win_rate = if (self.total_hands_played > 0)
                @as(f64, @floatFromInt(self.total_hands_won)) / @as(f64, @floatFromInt(self.total_hands_played))
            else
                0.0;

            self.average_roi = @as(f64, @floatFromInt(self.total_chips_won)) / @as(f64, @floatFromInt(self.tournaments_played));
        }
    }
};

/// Worker thread context for parallel execution
const WorkerContext = struct {
    worker_id: u32,
    config: *const ParallelTournamentConfig,
    result_queue: *std.Thread.Pool.Task,
    allocator: std.mem.Allocator,

    // Thread-local random number generator
    rng: std.Random,

    pub fn init(worker_id: u32, config: *const ParallelTournamentConfig, allocator: std.mem.Allocator) WorkerContext {
        var seed_bytes: [8]u8 = undefined;
        std.crypto.random.bytes(&seed_bytes);
        const seed = std.mem.readInt(u64, &seed_bytes, .little);

        var prng = std.rand.DefaultPrng.init(seed);

        return WorkerContext{
            .worker_id = worker_id,
            .config = config,
            .result_queue = undefined,
            .allocator = allocator,
            .rng = prng.random(),
        };
    }
};

/// Parallel tournament executor
pub const ParallelTournamentRunner = struct {
    config: ParallelTournamentConfig,
    allocator: std.mem.Allocator,
    thread_pool: std.Thread.Pool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ParallelTournamentConfig) !Self {
        try config.validate();

        return Self{
            .config = config,
            .allocator = allocator,
            .thread_pool = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
    }

    /// Run parallel tournaments and collect results
    pub fn runTournaments(self: *Self) !AggregatedResults {
        // Initialize thread pool
        try self.thread_pool.init(.{
            .allocator = self.allocator,
            .n_jobs = self.config.num_worker_threads,
        });

        var results = AggregatedResults.init(self.allocator);
        var results_mutex = std.Thread.Mutex{};

        // Create tasks for tournaments
        var tasks = std.ArrayList(TournamentTask).init(self.allocator);
        defer tasks.deinit();

        for (0..self.config.num_tournaments) |i| {
            const task = TournamentTask{
                .tournament_id = @intCast(i),
                .config = &self.config,
                .results = &results,
                .results_mutex = &results_mutex,
                .allocator = self.allocator,
            };
            try tasks.append(task);
        }

        // Submit tasks to thread pool
        for (tasks.items) |*task| {
            try self.thread_pool.spawn(runSingleTournament, .{task});
        }

        // Wait for completion
        while (self.thread_pool.totalJobs() > 0) {
            std.time.sleep(1000000); // Sleep 1ms
        }

        return results;
    }
};

/// Task structure for individual tournament execution
const TournamentTask = struct {
    tournament_id: u32,
    config: *const ParallelTournamentConfig,
    results: *AggregatedResults,
    results_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
};

/// Execute a single tournament in worker thread
fn runSingleTournament(task: *TournamentTask) void {
    const start_time = std.time.milliTimestamp();

    // Create thread-local tournament result
    var result = TournamentResult.init(task.allocator, task.tournament_id);
    defer result.deinit();

    // Initialize tournament
    var tournament = Tournament.init(
        task.allocator,
        task.config.format,
        task.config.max_players,
        task.config.initial_stack,
        task.config.blind_levels,
        createThreadRng(),
    ) catch |err| {
        std.debug.print("Failed to initialize tournament {}: {}\n", .{ task.tournament_id, err });
        return;
    };
    defer tournament.deinit();

    // Add players
    for (task.config.player_ids, task.config.initial_elo_ratings) |player_id, elo_rating| {
        tournament.addPlayer(player_id, elo_rating) catch |err| {
            std.debug.print("Failed to add player {} to tournament {}: {}\n", .{ player_id, task.tournament_id, err });
            return;
        };
    }

    // Set payout structure
    if (task.config.payout_positions.len > 0) {
        tournament.setPayoutStructure(task.config.payout_positions, task.config.payout_percentages) catch |err| {
            std.debug.print("Failed to set payout structure for tournament {}: {}\n", .{ task.tournament_id, err });
            return;
        };
    }

    // Initialize game engine
    var game_engine_instance = game_engine.GameEngine.init(task.allocator) catch |err| {
        std.debug.print("Failed to initialize game engine for tournament {}: {}\n", .{ task.tournament_id, err });
        return;
    };
    defer game_engine_instance.deinit();

    // Run tournament until completion
    while (!tournament.isComplete()) {
        tournament.runHand(&game_engine_instance) catch |err| {
            std.debug.print("Error running hand in tournament {}: {}\n", .{ task.tournament_id, err });
            break;
        };

        // Safety check to prevent infinite loops
        if (tournament.current_hand > 10000) {
            std.debug.print("Tournament {} exceeded maximum hands, terminating\n", .{task.tournament_id});
            break;
        }
    }

    // Finalize tournament
    tournament.finalizeTournament() catch |err| {
        std.debug.print("Failed to finalize tournament {}: {}\n", .{ task.tournament_id, err });
    };

    // Collect results
    result.summary = tournament.getTournamentSummary();
    result.execution_time_ms = @intCast(std.time.milliTimestamp() - start_time);

    // Copy player statistics
    var stats_iter = tournament.player_stats.iterator();
    while (stats_iter.next()) |entry| {
        result.player_stats.put(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
            std.debug.print("Failed to copy stats for tournament {}: {}\n", .{ task.tournament_id, err });
        };
    }

    // Thread-safe result aggregation
    task.results_mutex.lock();
    defer task.results_mutex.unlock();

    task.results.addTournamentResult(&result) catch |err| {
        std.debug.print("Failed to aggregate results for tournament {}: {}\n", .{ task.tournament_id, err });
    };
}

/// Create thread-local random number generator
fn createThreadRng() std.Random {
    var seed_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&seed_bytes);
    const seed = std.mem.readInt(u64, &seed_bytes, .little);
    var prng = std.rand.DefaultPrng.init(seed);
    return prng.random();
}

/// Utility functions for common tournament configurations
pub const TournamentConfigurations = struct {
    /// Standard heads-up tournament configuration
    pub fn headsUpConfig(
        allocator: std.mem.Allocator,
        num_tournaments: u32,
        num_threads: u32,
        player1_id: u8,
        player2_id: u8,
        initial_elo1: f64,
        initial_elo2: f64,
    ) !ParallelTournamentConfig {
        const blind_levels = [_]BlindLevel{
            tournament_mod.BlindLevel.init(5, 10, 0, 10),
            tournament_mod.BlindLevel.init(10, 20, 0, 10),
            tournament_mod.BlindLevel.init(25, 50, 0, 10),
            tournament_mod.BlindLevel.init(50, 100, 0, 10),
        };

        const owned_levels = try allocator.dupe(BlindLevel, &blind_levels);

        const player_ids = [_]u8{ player1_id, player2_id };
        const elo_ratings = [_]f64{ initial_elo1, initial_elo2 };

        const owned_player_ids = try allocator.dupe(u8, &player_ids);
        const owned_elo_ratings = try allocator.dupe(f64, &elo_ratings);

        const payout_positions = [_]u32{1};
        const payout_percentages = [_]f64{1.0};

        const owned_positions = try allocator.dupe(u32, &payout_positions);
        const owned_percentages = try allocator.dupe(f64, &payout_percentages);

        return ParallelTournamentConfig{
            .format = .heads_up,
            .max_players = 2,
            .initial_stack = 1000,
            .blind_levels = owned_levels,
            .payout_positions = owned_positions,
            .payout_percentages = owned_percentages,
            .num_tournaments = num_tournaments,
            .num_worker_threads = num_threads,
            .batch_size = 10,
            .player_ids = owned_player_ids,
            .initial_elo_ratings = owned_elo_ratings,
            .collect_detailed_stats = true,
            .collect_hand_history = false,
        };
    }

    /// Standard 6-player Sit-N-Go configuration
    pub fn sngConfig(
        allocator: std.mem.Allocator,
        num_tournaments: u32,
        num_threads: u32,
        player_ids: []const u8,
        initial_elos: []const f64,
    ) !ParallelTournamentConfig {
        const blind_levels = [_]BlindLevel{
            tournament_mod.BlindLevel.init(10, 20, 0, 20),
            tournament_mod.BlindLevel.init(25, 50, 0, 20),
            tournament_mod.BlindLevel.init(50, 100, 0, 20),
            tournament_mod.BlindLevel.init(100, 200, 25, 20),
            tournament_mod.BlindLevel.init(200, 400, 50, 20),
        };

        const owned_levels = try allocator.dupe(BlindLevel, &blind_levels);
        const owned_player_ids = try allocator.dupe(u8, player_ids);
        const owned_elo_ratings = try allocator.dupe(f64, initial_elos);

        const payout_positions = [_]u32{ 1, 2, 3 };
        const payout_percentages = [_]f64{ 0.50, 0.30, 0.20 };

        const owned_positions = try allocator.dupe(u32, &payout_positions);
        const owned_percentages = try allocator.dupe(f64, &payout_percentages);

        return ParallelTournamentConfig{
            .format = .sit_n_go,
            .max_players = 6,
            .initial_stack = 1500,
            .blind_levels = owned_levels,
            .payout_positions = owned_positions,
            .payout_percentages = owned_percentages,
            .num_tournaments = num_tournaments,
            .num_worker_threads = num_threads,
            .batch_size = 5,
            .player_ids = owned_player_ids,
            .initial_elo_ratings = owned_elo_ratings,
            .collect_detailed_stats = true,
            .collect_hand_history = false,
        };
    }
};
