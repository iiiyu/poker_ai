//! Simplified Tournament System Tests
//! Basic tests for tournament functionality to verify compilation

const std = @import("std");
const testing = std.testing;
const tournament_mod = @import("../src/tournament.zig");

const Tournament = tournament_mod.Tournament;
const TournamentFormat = tournament_mod.TournamentFormat;
const BlindLevel = tournament_mod.BlindLevel;
const BlindSchedule = tournament_mod.BlindSchedule;
const PlayerStats = tournament_mod.PlayerStats;
const ELOCalculator = tournament_mod.ELOCalculator;

test "BlindLevel basic functionality" {
    const level = BlindLevel.init(10, 20, 0, 30);
    
    try testing.expect(level.small_blind == 10);
    try testing.expect(level.big_blind == 20);
    try testing.expect(level.ante == 0);
    try testing.expect(level.duration_hands == 30);
}

test "BlindSchedule basic test" {
    const allocator = testing.allocator;
    
    const levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 2),
        BlindLevel.init(15, 30, 0, 2),
    };
    
    var schedule = try BlindSchedule.init(allocator, &levels);
    defer schedule.deinit();
    
    // Test initial state
    const current = schedule.getCurrentBlinds();
    try testing.expect(current.small_blind == 10);
    try testing.expect(current.big_blind == 20);
}

test "PlayerStats basic functionality" {
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
    
    // Test calculated metrics
    try testing.expect(stats.getWinRate() == 1.0); // 100% win rate with 1 hand won
    try testing.expect(stats.getROI() == 0.2); // 200/1000 = 0.2
}

test "ELO rating calculation" {
    const rating_a = 1500.0;
    const rating_b = 1600.0;
    
    const expected_score = ELOCalculator.calculateExpectedScore(rating_a, rating_b);
    try testing.expect(expected_score > 0.0 and expected_score < 1.0);
    try testing.expect(expected_score < 0.5); // Lower rated player should have < 50% expected score
    
    const new_rating = ELOCalculator.updateRating(rating_a, expected_score, 1.0); // Player A wins
    try testing.expect(new_rating > rating_a); // Rating should increase after unexpected win
}

test "Tournament format string conversion" {
    try testing.expectEqualStrings("cash_game", TournamentFormat.cash_game.toString());
    try testing.expectEqualStrings("freezeout", TournamentFormat.freezeout.toString());
    try testing.expectEqualStrings("sit_n_go", TournamentFormat.sit_n_go.toString());
    try testing.expectEqualStrings("heads_up", TournamentFormat.heads_up.toString());
}