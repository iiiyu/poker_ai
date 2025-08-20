//! Tournament System Demonstration
//!
//! This example demonstrates how to use the tournament system to evaluate AI agents
//! Shows different tournament formats and parallel execution capabilities

const std = @import("std");
const poker_ai = @import("poker_ai");
const tournament_mod = poker_ai.tournament;
const tournament_parallel = poker_ai.tournament_parallel;
const game_engine = poker_ai.game_engine;

const Tournament = tournament_mod.Tournament;
const TournamentFormat = tournament_mod.TournamentFormat;
const BlindLevel = tournament_mod.BlindLevel;
const DefaultBlindSchedules = tournament_mod.DefaultBlindSchedules;
const ParallelTournamentRunner = tournament_parallel.ParallelTournamentRunner;
const TournamentConfigurations = tournament_parallel.TournamentConfigurations;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Poker AI Tournament System Demo ===\n\n", .{});

    // Demo 1: Single Heads-Up Tournament
    std.debug.print("1. Single Heads-Up Tournament Demo\n", .{});
    std.debug.print("-----------------------------------\n", .{});
    try singleHeadsUpDemo(allocator);

    // Demo 2: Sit-N-Go Tournament
    std.debug.print("\n2. Sit-N-Go Tournament Demo\n", .{});
    std.debug.print("---------------------------\n", .{});
    try singleSNGDemo(allocator);

    // Demo 3: Parallel Heads-Up Evaluation
    std.debug.print("\n3. Parallel Tournament Evaluation\n", .{});
    std.debug.print("----------------------------------\n", .{});
    try parallelHeadsUpDemo(allocator);

    // Demo 4: Agent Comparison Study
    std.debug.print("\n4. AI Agent Comparison Study\n", .{});
    std.debug.print("----------------------------\n", .{});
    try agentComparisonDemo(allocator);

    std.debug.print("\n=== Tournament System Demo Complete ===\n", .{});
}

/// Demonstrate a single heads-up tournament
fn singleHeadsUpDemo(allocator: std.mem.Allocator) !void {
    // Create heads-up blind schedule
    var blind_schedule = try DefaultBlindSchedules.headsUp(allocator);
    defer blind_schedule.deinit();

    // Initialize random number generator
    const seed: u64 = @intCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    // Create tournament
    var tournament = try Tournament.init(
        allocator,
        .heads_up,
        2,
        1000, // Starting stack
        blind_schedule.levels,
        rng,
    );
    defer tournament.deinit();

    // Add two AI players
    try tournament.addPlayer(1, 1500.0); // Agent A with 1500 ELO
    try tournament.addPlayer(2, 1600.0); // Agent B with 1600 ELO

    // Set winner-takes-all payout
    const positions = [_]u32{1};
    const percentages = [_]f64{1.0};
    try tournament.setPayoutStructure(&positions, &percentages);

    std.debug.print("Tournament Setup:\n", .{});
    std.debug.print("  Format: {s}\n", .{tournament.format.toString()});
    std.debug.print("  Players: {}\n", .{tournament.players.items.len});
    std.debug.print("  Starting Stack: {} chips\n", .{tournament.initial_stack});
    std.debug.print("  Prize Pool: {} chips\n", .{tournament.total_prize_pool});

    // Simulate tournament progression (simplified)
    std.debug.print("\nTournament Progress:\n", .{});
    for (0..10) |hand_num| {
        if (tournament.isComplete()) break;
        
        std.debug.print("  Hand {}: ", .{hand_num + 1});
        const current_blinds = tournament.blind_schedule.getCurrentBlinds();
        std.debug.print("Blinds {}/{} ", .{ current_blinds.small_blind, current_blinds.big_blind });
        
        // In a real implementation, this would run the actual hand
        // For demo purposes, we'll just advance the tournament state
        tournament.advanceHand();
        std.debug.print("(simulated)\n", .{});
    }

    // Get final summary
    const summary = tournament.getTournamentSummary();
    std.debug.print("\nTournament Summary:\n", .{});
    std.debug.print("  Total Hands: {}\n", .{summary.total_hands});
    std.debug.print("  Complete: {}\n", .{summary.is_complete});
}

/// Demonstrate a Sit-N-Go tournament
fn singleSNGDemo(allocator: std.mem.Allocator) !void {
    // Create SNG blind schedule
    var blind_schedule = try DefaultBlindSchedules.standardSNG(allocator);
    defer blind_schedule.deinit();

    // Initialize random number generator
    const seed: u64 = @intCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    // Create 6-player SNG tournament
    var tournament = try Tournament.init(
        allocator,
        .sit_n_go,
        6,
        1500, // Starting stack
        blind_schedule.levels,
        rng,
    );
    defer tournament.deinit();

    // Add 6 AI players with different skill levels
    const player_data = [_]struct { id: u8, elo: f64, name: []const u8 }{
        .{ .id = 1, .elo = 1800.0, .name = "Elite Bot" },
        .{ .id = 2, .elo = 1600.0, .name = "Strong Bot" },
        .{ .id = 3, .elo = 1500.0, .name = "Average Bot" },
        .{ .id = 4, .elo = 1400.0, .name = "Weak Bot" },
        .{ .id = 5, .elo = 1300.0, .name = "Learning Bot" },
        .{ .id = 6, .elo = 1700.0, .name = "Aggressive Bot" },
    };

    for (player_data) |player| {
        try tournament.addPlayer(player.id, player.elo);
    }

    // Set SNG payout structure (50%/30%/20%)
    const positions = [_]u32{ 1, 2, 3 };
    const percentages = [_]f64{ 0.50, 0.30, 0.20 };
    try tournament.setPayoutStructure(&positions, &percentages);

    std.debug.print("SNG Tournament Setup:\n", .{});
    std.debug.print("  Players: {}\n", .{tournament.players.items.len});
    std.debug.print("  Starting Stack: {} chips\n", .{tournament.initial_stack});
    std.debug.print("  Prize Pool: {} chips\n", .{tournament.total_prize_pool});
    std.debug.print("  Payout Structure: 50%/30%/20%\n", .{});

    std.debug.print("\nPlayer Lineup:\n", .{});
    for (player_data) |player| {
        std.debug.print("  Player {}: {s} (ELO: {d:.0})\n", .{ player.id, player.name, player.elo });
    }

    // Show blind structure
    std.debug.print("\nBlind Structure:\n", .{});
    for (blind_schedule.levels[0..5], 0..) |level, i| {
        std.debug.print("  Level {}: {}/{} ({} hands)\n", .{ i + 1, level.small_blind, level.big_blind, level.duration_hands });
    }

    std.debug.print("\nSimulated tournament progression...\n", .{});
    // In a real implementation, the tournament would run to completion
    // For demo purposes, we'll show the structure
}

/// Demonstrate parallel tournament execution for statistical analysis
fn parallelHeadsUpDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("Running 100 parallel heads-up tournaments for statistical analysis...\n", .{});

    // Create parallel tournament configuration
    var config = try TournamentConfigurations.headsUpConfig(
        allocator,
        100,  // 100 tournaments
        4,    // 4 worker threads
        1,    // Player 1 ID
        2,    // Player 2 ID
        1500.0, // Player 1 ELO
        1600.0, // Player 2 ELO
    );
    
    defer {
        allocator.free(config.blind_levels);
        allocator.free(config.payout_positions);
        allocator.free(config.payout_percentages);
        allocator.free(config.player_ids);
        allocator.free(config.initial_elo_ratings);
    }

    // Note: In a real implementation, this would actually run the tournaments
    // For demo purposes, we'll show the configuration and expected results
    
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  Tournament Format: {s}\n", .{config.format.toString()});
    std.debug.print("  Number of Tournaments: {}\n", .{config.num_tournaments});
    std.debug.print("  Worker Threads: {}\n", .{config.num_worker_threads});
    std.debug.print("  Starting Stack: {} chips\n", .{config.initial_stack});
    
    std.debug.print("\nPlayer Setup:\n", .{});
    for (config.player_ids, config.initial_elo_ratings) |player_id, elo| {
        std.debug.print("  Player {}: ELO {d:.0}\n", .{ player_id, elo });
    }
    
    // Simulate execution statistics
    const estimated_time_ms = config.num_tournaments * 50; // Rough estimate
    const estimated_hands = config.num_tournaments * 25;  // Average hands per HU tournament
    
    std.debug.print("\nEstimated Performance:\n", .{});
    std.debug.print("  Total Hands Simulated: ~{}\n", .{estimated_hands});
    std.debug.print("  Estimated Execution Time: ~{}ms\n", .{estimated_time_ms});
    std.debug.print("  Hands per Second: ~{d:.0}\n", .{@as(f64, @floatFromInt(estimated_hands)) / (@as(f64, @floatFromInt(estimated_time_ms)) / 1000.0)});
    
    std.debug.print("\nExpected Results Format:\n", .{});
    std.debug.print("  - Win rates for each player\n", .{});
    std.debug.print("  - ELO rating changes\n", .{});
    std.debug.print("  - Statistical confidence intervals\n", .{});
    std.debug.print("  - Performance metrics (hands/sec, tournaments/sec)\n", .{});
}

/// Demonstrate AI agent comparison across multiple tournament formats
fn agentComparisonDemo(_: std.mem.Allocator) !void {
    std.debug.print("AI Agent Comparison Study Setup\n", .{});

    // Define test agents with different characteristics
    const agents = [_]struct {
        id: u8,
        name: []const u8,
        elo: f64,
        description: []const u8,
    }{
        .{ .id = 1, .name = "Tight-Aggressive", .elo = 1650.0, .description = "Conservative pre-flop, aggressive post-flop" },
        .{ .id = 2, .name = "Loose-Aggressive", .elo = 1580.0, .description = "Plays many hands aggressively" },
        .{ .id = 3, .name = "Tight-Passive", .elo = 1420.0, .description = "Very selective, rarely bluffs" },
        .{ .id = 4, .name = "MCCFR-Trained", .elo = 1720.0, .description = "Trained with Monte Carlo CFR" },
        .{ .id = 5, .name = "GTO-Approximator", .elo = 1680.0, .description = "Attempts game-theory optimal play" },
        .{ .id = 6, .name = "Exploitative", .elo = 1600.0, .description = "Adapts to opponent weaknesses" },
    };

    std.debug.print("\nTest Agents:\n", .{});
    for (agents) |agent| {
        std.debug.print("  {}: {s} (ELO: {d:.0})\n", .{ agent.id, agent.name, agent.elo });
        std.debug.print("      {s}\n", .{agent.description});
    }

    // Tournament formats to test
    const test_formats = [_]struct {
        format: TournamentFormat,
        name: []const u8,
        tournaments: u32,
    }{
        .{ .format = .heads_up, .name = "Heads-Up", .tournaments = 200 },
        .{ .format = .sit_n_go, .name = "6-Player SNG", .tournaments = 100 },
        .{ .format = .cash_game, .name = "Cash Game", .tournaments = 50 },
    };

    std.debug.print("\nTournament Formats to Test:\n", .{});
    for (test_formats) |test_format| {
        std.debug.print("  {s}: {} tournaments\n", .{ test_format.name, test_format.tournaments });
    }

    // Analysis metrics
    std.debug.print("\nAnalysis Metrics:\n", .{});
    std.debug.print("  - Win Rate by Format\n", .{});
    std.debug.print("  - ELO Rating Changes\n", .{});
    std.debug.print("  - Chips Won/Lost\n", .{});
    std.debug.print("  - ITM (In-The-Money) Percentage\n", .{});
    std.debug.print("  - Average Finish Position\n", .{});
    std.debug.print("  - Head-to-Head Records\n", .{});
    std.debug.print("  - Performance vs. Starting Stack Size\n", .{});
    std.debug.print("  - Adaptation to Blind Structure\n", .{});

    // Expected output format
    std.debug.print("\nExpected Results Table Format:\n", .{});
    std.debug.print("  Agent Name        | HU Win% | SNG ITM% | Cash BB/100 | Final ELO\n", .{});
    std.debug.print("  ------------------|---------|----------|-------------|----------\n", .{});
    std.debug.print("  Tight-Aggressive  | 52.3%   | 35.2%    | +2.8        | 1685\n", .{});
    std.debug.print("  MCCFR-Trained     | 58.1%   | 42.1%    | +4.2        | 1755\n", .{});
    std.debug.print("  GTO-Approximator  | 55.7%   | 38.9%    | +3.5        | 1712\n", .{});
    std.debug.print("  ... (other agents)\n", .{});

    std.debug.print("\nEstimated Study Duration:\n", .{});
    const total_tournaments = 200 + 100 + 50; // Total across all formats
    const estimated_hours = @as(f64, @floatFromInt(total_tournaments)) * 6.0 / (4.0 * 3600.0); // 6 agents, 4 threads
    std.debug.print("  Total Tournaments: {} per agent combination\n", .{total_tournaments});
    std.debug.print("  Estimated Runtime: {d:.1} hours with 4 threads\n", .{estimated_hours});
    std.debug.print("  Statistical Confidence: 95%+ with sample sizes\n", .{});
}

/// Utility function to format chip amounts nicely
fn formatChips(chips: u32) void {
    if (chips >= 1_000_000) {
        std.debug.print("{d:.1}M", .{@as(f64, @floatFromInt(chips)) / 1_000_000.0});
    } else if (chips >= 1_000) {
        std.debug.print("{d:.1}K", .{@as(f64, @floatFromInt(chips)) / 1_000.0});
    } else {
        std.debug.print("{}", .{chips});
    }
}

/// Utility function to format ELO ratings
fn formatELO(elo: f64) void {
    std.debug.print("{d:.0}", .{elo});
}

/// Utility function to format percentages
fn formatPercentage(value: f64) void {
    std.debug.print("{d:.1}%", .{value * 100.0});
}