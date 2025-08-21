//! Standalone tournament test to verify basic functionality

const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("Testing tournament system compilation...\n", .{});

    // Import tournament module
    const tournament_mod = @import("src/tournament.zig");
    const BlindLevel = tournament_mod.BlindLevel;
    const BlindSchedule = tournament_mod.BlindSchedule;
    const Tournament = tournament_mod.Tournament;
    const PlayerStats = tournament_mod.PlayerStats;
    const DefaultBlindSchedules = tournament_mod.DefaultBlindSchedules;

    // Test 1: BlindLevel creation
    const level = BlindLevel.init(10, 20, 0, 30);
    print("✓ BlindLevel created: {}/{} ante:{} duration:{}\n", .{ level.small_blind, level.big_blind, level.ante, level.duration_hands });

    // Test 2: PlayerStats creation and updates
    var stats = PlayerStats.init(1, 1000, 1500.0);
    stats.updateHandResult(200, true);
    print("✓ PlayerStats: player={} hands={} won={} chips_won={} elo={d:.0}\n", .{ stats.player_id, stats.hands_played, stats.hands_won, stats.chips_won, stats.elo_rating });

    // Test 3: BlindSchedule creation
    const levels = [_]BlindLevel{
        BlindLevel.init(10, 20, 0, 5),
        BlindLevel.init(20, 40, 0, 5),
    };
    var schedule = try BlindSchedule.init(allocator, &levels);
    defer schedule.deinit();
    print("✓ BlindSchedule created with {} levels\n", .{schedule.levels.len});

    // Test 4: Default blind schedules
    var sng_schedule = try DefaultBlindSchedules.standardSNG(allocator);
    defer sng_schedule.deinit();
    print("✓ Standard SNG schedule created with {} levels\n", .{sng_schedule.levels.len});

    var hu_schedule = try DefaultBlindSchedules.headsUp(allocator);
    defer hu_schedule.deinit();
    print("✓ Heads-up schedule created with {} levels\n", .{hu_schedule.levels.len});

    // Test 5: Tournament creation
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
    print("✓ Tournament created: format=heads_up, max_players=2, initial_stack=1000\n", .{});

    // Test 6: Add players
    try tournament.addPlayer(1, 1500.0);
    try tournament.addPlayer(2, 1600.0);
    print("✓ Players added: count={}, prize_pool={}\n", .{ tournament.players.items.len, tournament.total_prize_pool });

    print("\n=== All tournament system components compiled and tested successfully! ===\n", .{});
}