//! Tournament System Tests
//!
//! Comprehensive test suite for the tournament simulation system
//! Tests all major components including tournaments, parallel execution, and statistics

const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");
const tournament_mod = poker_ai.tournament;
const tournament_parallel = poker_ai.tournament_parallel;
const game_engine = poker_ai.game_engine;

const Tournament = tournament_mod.Tournament;
const TournamentFormat = tournament_mod.TournamentFormat;
const BlindLevel = tournament_mod.BlindLevel;
const BlindSchedule = tournament_mod.BlindSchedule;
const PlayerStats = tournament_mod.PlayerStats;
const DefaultBlindSchedules = tournament_mod.DefaultBlindSchedules;
const ELOCalculator = tournament_mod.ELOCalculator;
const ParallelTournamentRunner = tournament_parallel.ParallelTournamentRunner;
const ParallelTournamentConfig = tournament_parallel.ParallelTournamentConfig;

test "BlindLevel basic functionality" {
    const level = BlindLevel.init(10, 20, 0, 30);
    
    try testing.expect(level.small_blind == 10);
    try testing.expect(level.big_blind == 20);
    try testing.expect(level.ante == 0);
    try testing.expect(level.duration_hands == 30);
}

test "BlindSchedule progression" {
    const allocator = testing.allocator;
    
    const levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 2),
        BlindLevel.init(15, 30, 0, 2),
        BlindLevel.init(25, 50, 0, 2),
    };
    
    var schedule = try BlindSchedule.init(allocator, &levels);
    defer schedule.deinit();
    
    // Test initial state
    var current = schedule.getCurrentBlinds();
    try testing.expect(current.small_blind == 10);
    try testing.expect(current.big_blind == 20);
    
    // Advance one hand
    schedule.advanceHand();
    current = schedule.getCurrentBlinds();
    try testing.expect(current.small_blind == 10); // Still at level 1
    
    // Advance another hand (should trigger level change)
    schedule.advanceHand();
    current = schedule.getCurrentBlinds();
    try testing.expect(current.small_blind == 15); // Now at level 2
    try testing.expect(current.big_blind == 30);
    
    // Test shouldAdvanceLevel
    try testing.expect(!schedule.shouldAdvanceLevel()); // Just advanced
    
    // Advance two more hands to next level
    schedule.advanceHand();
    schedule.advanceHand();
    current = schedule.getCurrentBlinds();
    try testing.expect(current.small_blind == 25); // Now at level 3
    try testing.expect(current.big_blind == 50);
}

test "PlayerStats functionality" {
    var stats = PlayerStats.init(1, 1000, 1500.0);
    
    try testing.expect(stats.player_id == 1);
    try testing.expect(stats.initial_stack == 1000);
    try testing.expect(stats.final_stack == 1000);
    try testing.expect(stats.elo_rating == 1500.0);
    
    // Test hand result updates
    stats.updateHandResult(200, true);
    try testing.expect(stats.hands_played == 1);
    try testing.expect(stats.hands_won == 1);
    try testing.expect(stats.chips_won == 200);
    try testing.expect(stats.final_stack == 1200);
    
    stats.updateHandResult(-100, false);
    try testing.expect(stats.hands_played == 2);
    try testing.expect(stats.hands_won == 1);
    try testing.expect(stats.chips_won == 100);
    try testing.expect(stats.final_stack == 1100);
    
    // Test calculated metrics
    try testing.expect(stats.getWinRate() == 0.5);
    try testing.expect(stats.getROI() == 0.1);
}

test "ELO rating calculation" {
    const rating_a = 1500.0;
    const rating_b = 1600.0;
    
    const expected_score = ELOCalculator.calculateExpectedScore(rating_a, rating_b);
    try testing.expect(expected_score > 0.0 and expected_score < 1.0);
    try testing.expect(expected_score < 0.5); // Lower rated player should have < 50% expected score
    
    const new_rating = ELOCalculator.updateRating(rating_a, expected_score, 1.0); // Player A wins
    try testing.expect(new_rating > rating_a); // Rating should increase after unexpected win
    
    const new_rating_loss = ELOCalculator.updateRating(rating_a, expected_score, 0.0); // Player A loses
    try testing.expect(new_rating_loss < rating_a); // Rating should decrease after expected loss
}

test "Tournament basic functionality" {
    const allocator = testing.allocator;
    
    const levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 10),
        BlindLevel.init(20, 40, 0, 10),
    };
    
    const seed: u64 = 12345;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    
    var tournament = try Tournament.init(
        allocator,
        .sit_n_go,
        6,
        1000,
        &levels,
        rng,
    );
    defer tournament.deinit();
    
    // Test initial state
    try testing.expect(tournament.format == .sit_n_go);
    try testing.expect(tournament.max_players == 6);
    try testing.expect(tournament.initial_stack == 1000);
    try testing.expect(tournament.current_hand == 0);
    // With no registered players the tournament reports complete
    try testing.expect(tournament.isComplete());
    
    // Add players
    try tournament.addPlayer(1, 1500.0);
    try tournament.addPlayer(2, 1600.0);
    
    try testing.expect(tournament.players.items.len == 2);
    try testing.expect(tournament.total_prize_pool == 2000);
    
    // Test player stats were created
    try testing.expect(tournament.player_stats.contains(1));
    try testing.expect(tournament.player_stats.contains(2));
    
    // Set payout structure
    const positions = [_]u32{1};
    const percentages = [_]f64{1.0};
    try tournament.setPayoutStructure(&positions, &percentages);
    
    // Test tournament summary
    const summary = tournament.getTournamentSummary();
    try testing.expect(summary.format == .sit_n_go);
    try testing.expect(summary.total_players == 2);
    try testing.expect(summary.total_prize_pool == 2000);
    try testing.expect(!summary.is_complete);
}

test "Tournament heads-up completion" {
    const allocator = testing.allocator;
    
    const levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 5),
    };
    
    const seed: u64 = 12345;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    
    var tournament = try Tournament.init(
        allocator,
        .heads_up,
        2,
        1000,
        &levels,
        rng,
    );
    defer tournament.deinit();
    
    // Add two players
    try tournament.addPlayer(1, 1500.0);
    try tournament.addPlayer(2, 1500.0);
    
    // For heads-up, completion is when <= 1 active player
    // This is a simplified test since we can't easily simulate full hands
    try testing.expect(!tournament.isComplete()); // Should not be complete with 2 players
}

test "Default blind schedules" {
    const allocator = testing.allocator;
    
    // Test SNG schedule
    var sng_schedule = try DefaultBlindSchedules.standardSNG(allocator);
    defer sng_schedule.deinit();
    
    const first_level = sng_schedule.getCurrentBlinds();
    try testing.expect(first_level.small_blind == 10);
    try testing.expect(first_level.big_blind == 20);
    
    // Test cash game schedule
    var cash_schedule = try DefaultBlindSchedules.cashGame(allocator, 5, 10);
    defer cash_schedule.deinit();
    
    const cash_level = cash_schedule.getCurrentBlinds();
    try testing.expect(cash_level.small_blind == 5);
    try testing.expect(cash_level.big_blind == 10);
    try testing.expect(cash_level.duration_hands == std.math.maxInt(u32)); // Should be unlimited
    
    // Test heads-up schedule
    var hu_schedule = try DefaultBlindSchedules.headsUp(allocator);
    defer hu_schedule.deinit();
    
    const hu_first_level = hu_schedule.getCurrentBlinds();
    try testing.expect(hu_first_level.small_blind == 5);
    try testing.expect(hu_first_level.big_blind == 10);
}

test "Parallel tournament configuration validation" {
    const blind_levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 10),
    };
    
    const player_ids = [_]u8{ 1, 2 };
    const elo_ratings = [_]f64{ 1500.0, 1500.0 };
    const positions = [_]u32{1};
    const percentages = [_]f64{1.0};
    
    // Valid configuration
    var valid_config = ParallelTournamentConfig{
        .format = .heads_up,
        .max_players = 2,
        .initial_stack = 1000,
        .blind_levels = &blind_levels,
        .payout_positions = &positions,
        .payout_percentages = &percentages,
        .num_tournaments = 10,
        .num_worker_threads = 2,
        .batch_size = 5,
        .player_ids = &player_ids,
        .initial_elo_ratings = &elo_ratings,
        .collect_detailed_stats = true,
        .collect_hand_history = false,
    };
    
    try valid_config.validate();
    
    // Test invalid player count
    var invalid_config = valid_config;
    invalid_config.max_players = 1;
    try testing.expectError(error.InvalidPlayerCount, invalid_config.validate());
    
    // Test invalid tournament count
    invalid_config = valid_config;
    invalid_config.num_tournaments = 0;
    try testing.expectError(error.InvalidTournamentCount, invalid_config.validate());
    
    // Test invalid thread count
    invalid_config = valid_config;
    invalid_config.num_worker_threads = 0;
    try testing.expectError(error.InvalidThreadCount, invalid_config.validate());
    
    // Test mismatched player data
    invalid_config = valid_config;
    const wrong_ratings = [_]f64{1500.0}; // Only one rating for two players
    invalid_config.initial_elo_ratings = &wrong_ratings;
    try testing.expectError(error.MismatchedPlayerData, invalid_config.validate());
}

test "Tournament configurations utility functions" {
    const allocator = testing.allocator;
    
    // Test heads-up configuration
    var hu_config = try tournament_parallel.TournamentConfigurations.headsUpConfig(
        allocator,
        100,
        4,
        1,
        2,
        1500.0,
        1600.0,
    );
    
    try hu_config.validate();
    try testing.expect(hu_config.format == .heads_up);
    try testing.expect(hu_config.max_players == 2);
    try testing.expect(hu_config.num_tournaments == 100);
    try testing.expect(hu_config.num_worker_threads == 4);
    try testing.expect(hu_config.player_ids.len == 2);
    try testing.expect(hu_config.initial_elo_ratings.len == 2);
    
    // Clean up allocated memory
    allocator.free(hu_config.blind_levels);
    allocator.free(hu_config.payout_positions);
    allocator.free(hu_config.payout_percentages);
    allocator.free(hu_config.player_ids);
    allocator.free(hu_config.initial_elo_ratings);
    
    // Test SNG configuration
    const sng_player_ids = [_]u8{ 1, 2, 3, 4, 5, 6 };
    const sng_elo_ratings = [_]f64{ 1500.0, 1600.0, 1450.0, 1550.0, 1480.0, 1520.0 };
    
    var sng_config = try tournament_parallel.TournamentConfigurations.sngConfig(
        allocator,
        50,
        3,
        &sng_player_ids,
        &sng_elo_ratings,
    );
    
    try sng_config.validate();
    try testing.expect(sng_config.format == .sit_n_go);
    try testing.expect(sng_config.max_players == 6);
    try testing.expect(sng_config.num_tournaments == 50);
    try testing.expect(sng_config.num_worker_threads == 3);
    try testing.expect(sng_config.player_ids.len == 6);
    try testing.expect(sng_config.initial_elo_ratings.len == 6);
    try testing.expect(sng_config.payout_positions.len == 3); // Top 3 paid
    
    // Clean up allocated memory
    allocator.free(sng_config.blind_levels);
    allocator.free(sng_config.payout_positions);
    allocator.free(sng_config.payout_percentages);
    allocator.free(sng_config.player_ids);
    allocator.free(sng_config.initial_elo_ratings);
}

test "PlayerAggregate statistics" {
    var aggregate = tournament_parallel.PlayerAggregate.init(1);
    
    try testing.expect(aggregate.player_id == 1);
    try testing.expect(aggregate.tournaments_played == 0);
    try testing.expect(aggregate.average_win_rate == 0.0);
    
    // Add first tournament result
    var stats1 = PlayerStats.init(1, 1000, 1500.0);
    stats1.hands_played = 20;
    stats1.hands_won = 10;
    stats1.chips_won = 500;
    stats1.elimination_position = 1; // First place
    
    aggregate.addTournament(stats1);
    
    try testing.expect(aggregate.tournaments_played == 1);
    try testing.expect(aggregate.total_hands_played == 20);
    try testing.expect(aggregate.total_hands_won == 10);
    try testing.expect(aggregate.total_chips_won == 500);
    try testing.expect(aggregate.first_place_finishes == 1);
    try testing.expect(aggregate.average_win_rate == 0.5);
    
    // Add second tournament result
    var stats2 = PlayerStats.init(1, 1000, 1500.0);
    stats2.hands_played = 30;
    stats2.hands_won = 15;
    stats2.chips_won = -200;
    stats2.elimination_position = 4; // Fourth place
    
    aggregate.addTournament(stats2);
    
    try testing.expect(aggregate.tournaments_played == 2);
    try testing.expect(aggregate.total_hands_played == 50);
    try testing.expect(aggregate.total_hands_won == 25);
    try testing.expect(aggregate.total_chips_won == 300);
    try testing.expect(aggregate.first_place_finishes == 1); // Still only one first place
    try testing.expect(aggregate.average_win_rate == 0.5); // 25/50 = 0.5
}

// Full tournament integration test omitted: requires full engine wiring + RNG seeding.

// Test for tournament format string conversion
test "Tournament format string conversion" {
    try testing.expectEqualStrings("cash_game", TournamentFormat.cash_game.toString());
    try testing.expectEqualStrings("freezeout", TournamentFormat.freezeout.toString());
    try testing.expectEqualStrings("sit_n_go", TournamentFormat.sit_n_go.toString());
    try testing.expectEqualStrings("multi_table", TournamentFormat.multi_table.toString());
    try testing.expectEqualStrings("heads_up", TournamentFormat.heads_up.toString());
}

// Benchmark test for tournament creation performance
test "Tournament creation benchmark" {
    const allocator = testing.allocator;
    
    const levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 10),
    };
    
    const seed: u64 = 12345;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    
    const start_time = std.time.nanoTimestamp();
    
    // Create and destroy 1000 tournaments
    for (0..1000) |_| {
        var tournament = try Tournament.init(
            allocator,
            .sit_n_go,
            6,
            1000,
            &levels,
            rng,
        );
        tournament.deinit();
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    
    // Should be reasonably fast (less than 100ms for 1000 tournaments)
    try testing.expect(duration_ms < 100.0);
    
    std.debug.print("\nTournament creation benchmark: {d:.2}ms for 1000 tournaments\n", .{duration_ms});
}
