//! Complete MCCFR Training Executable for Poker AI
//! Implements full Monte Carlo CFR with Linear CFR improvements

const std = @import("std");
const system_config = @import("config.zig");
const io_helpers = @import("io_helpers.zig");
const poker_ai = @import("main.zig");
const game_state = @import("game_state.zig");
const linear_cfr = @import("linear_cfr.zig");
const game_tree = @import("game_tree.zig");

const GameState = game_state.GameState;
const LinearCFRTrainer = linear_cfr.LinearCFRTrainer;
const LinearCFRConfig = linear_cfr.LinearCFRConfig;

/// Training configuration from command line
const TrainingConfig = struct {
    iterations: u32 = 100_000,
    num_players: u8 = 2,
    threads: u32 = 8,
    checkpoint_interval: u32 = 5000,
    output_dir: []const u8 = "./strategies",
    use_linear_cfr: bool = true,
    discount_interval: u32 = 1000,
    exploration_epsilon: f32 = 0.6,
    print_progress: bool = true,
    calculate_exploitability: bool = true,
    exploitability_interval: u32 = 10000,
};

/// Progress tracker
const ProgressTracker = struct {
    start_time: i64,
    iterations_completed: u32,
    last_checkpoint: u32,
    best_exploitability: f32,
    
    pub fn init() ProgressTracker {
        return .{
            .start_time = std.time.milliTimestamp(),
            .iterations_completed = 0,
            .last_checkpoint = 0,
            .best_exploitability = std.math.inf(f32),
        };
    }
    
    pub fn printProgress(self: *ProgressTracker, iteration: u32, exploitability: ?f32) void {
        const elapsed_ms = std.time.milliTimestamp() - self.start_time;
        const elapsed_sec = @as(f32, @floatFromInt(elapsed_ms)) / 1000.0;
        const iter_per_sec = if (elapsed_sec > 0.001) 
            @as(f32, @floatFromInt(iteration)) / elapsed_sec
        else 
            0.0;
        
        std.debug.print("\r[Iteration {d:6}] ", .{iteration});
        std.debug.print("Speed: {d:.0} iter/s | ", .{iter_per_sec});
        
        if (exploitability) |exp| {
            std.debug.print("Exploitability: {d:.4} | ", .{exp});
            if (exp < self.best_exploitability) {
                self.best_exploitability = exp;
                std.debug.print("(New Best!) ", .{});
            }
        }
        
        std.debug.print("Time: {d:.1}s", .{elapsed_sec});
    }
};

/// Main training function
pub fn trainMCCFR(config: TrainingConfig, allocator: std.mem.Allocator) !void {
    std.log.info("Starting MCCFR Training", .{});
    std.log.info("Configuration:", .{});
    std.log.info("  Iterations: {d}", .{config.iterations});
    std.log.info("  Players: {d}", .{config.num_players});
    std.log.info("  Threads: {d}", .{config.threads});
    std.log.info("  Linear CFR: {}", .{config.use_linear_cfr});
    std.log.info("  Output: {s}", .{config.output_dir});
    
    // Create output directory
    std.fs.cwd().makeDir(config.output_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    
    // Initialize CFR trainer
    const cfr_config = LinearCFRConfig{
        .discount_positive = 1.5,
        .discount_negative = 0.5,
        .discount_interval = config.discount_interval,
        .prune_threshold = -300.0,
        .exploration_epsilon = config.exploration_epsilon,
        .use_averaging = true,
    };
    
    var trainer = try LinearCFRTrainer.init(allocator, cfr_config);
    defer trainer.deinit();
    
    // Progress tracker
    var progress = ProgressTracker.init();
    
    // Training loop with enhanced error handling
    var iteration: u32 = 0;
    var consecutive_errors: u32 = 0;
    
    while (iteration < config.iterations) : (iteration += 1) {
        // Create game for this iteration
        var game = GameState.init(allocator, config.num_players, 50, 100) catch |err| switch (err) {
            error.OutOfMemory => {
                std.log.err("Out of memory creating game state at iteration {d}", .{iteration});
                return err;
            },
            else => return err,
        };
        defer game.deinit();
        
        // Shuffle deck and deal cards
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp() + iteration));
        game.shuffleDeck(prng.random());
        
        // Deal hole cards
        var hands: [system_config.MAX_PLAYERS][2]game_state.Card = undefined;
        for (0..config.num_players) |p| {
            hands[p][0] = game.dealCard();
            hands[p][1] = game.dealCard();
        }
        game.dealHoleCards(hands[0..]);
        
        // Post blinds
        try game.postBlinds();
        
        // Run MCCFR iteration with error recovery
        const utility = trainer.iterate(&game) catch |err| switch (err) {
            error.OutOfMemory, error.InfoSetLimitExceeded => {
                std.log.err("Memory error at iteration {d}: {}", .{iteration, err});
                std.log.info("InfoSets created: {d}", .{trainer.infoset_map.count()});
                return err;
            },
            error.IterationOverflow => {
                std.log.err("Iteration counter overflow at {d}", .{iteration});
                return err;
            },
            error.NoLegalActions, error.TooManyActions => {
                consecutive_errors += 1;
                std.log.warn("Game state error at iteration {d}: {} (consecutive: {d})", .{iteration, err, consecutive_errors});
                
                if (consecutive_errors > 10) {
                    std.log.err("Too many consecutive game state errors, aborting", .{});
                    return error.TooManyConsecutiveErrors;
                }
                continue; // Skip this iteration
            },
            else => {
                std.log.err("Unexpected error at iteration {d}: {}", .{iteration, err});
                return err;
            },
        };
        
        // Reset consecutive error counter on success
        consecutive_errors = 0;
        _ = utility;
        
        // Progress reporting
        const report_interval: u32 = if (config.iterations < 100) 1 else 100;
        if (config.print_progress and iteration > 0 and iteration % report_interval == 0) {
            var exploitability: ?f32 = null;
            
            if (config.calculate_exploitability and iteration % config.exploitability_interval == 0) {
                exploitability = try trainer.calculateExploitability(&game);
            }
            
            progress.printProgress(iteration, exploitability);
        }
        
        // Checkpointing
        if (iteration % config.checkpoint_interval == 0 and iteration > 0) {
            const checkpoint_path = try std.fmt.allocPrint(
                allocator,
                "{s}/checkpoint_{d}.strat",
                .{ config.output_dir, iteration }
            );
            defer allocator.free(checkpoint_path);
            
            try saveStrategy(&trainer, checkpoint_path);
            std.log.info("\nCheckpoint saved: {s}", .{checkpoint_path});
        }
    }
    
    // Save final strategy
    const final_path = try std.fmt.allocPrint(
        allocator,
        "{s}/final_strategy.strat",
        .{config.output_dir}
    );
    defer allocator.free(final_path);
    
    try saveStrategy(&trainer, final_path);
    
    // Final statistics
    std.log.info("\n\nTraining Complete!", .{});
    std.log.info("Final strategy saved to: {s}", .{final_path});
    std.log.info("Total iterations: {d}", .{config.iterations});
    
    if (config.calculate_exploitability) {
        // Create a game state for exploitability calculation
        var final_game = try GameState.init(allocator, config.num_players, 50, 100);
        defer final_game.deinit();
        
        const final_exploitability = try trainer.calculateExploitability(&final_game);
        std.log.info("Final exploitability: {d:.6} mbb/hand", .{final_exploitability * 1000});
    }
    
    // Detailed memory statistics
    const infoset_count = trainer.infoset_map.count();
    var total_actions: usize = 0;
    var total_memory: usize = 0;
    
    // Calculate actual memory usage
    var iter = trainer.infoset_map.iterator();
    while (iter.next()) |entry| {
        const data = entry.value_ptr;
        const actions = data.regrets.len;
        total_actions += actions;
        total_memory += @sizeOf(linear_cfr.InfoSetData) + (3 * actions * @sizeOf(f32)); // regrets + strategy + strategy_sum
    }
    
    std.log.info("Information sets: {d}", .{infoset_count});
    std.log.info("Total actions stored: {d}", .{total_actions});
    std.log.info("Average actions per InfoSet: {d:.2}", .{if (infoset_count > 0) @as(f32, @floatFromInt(total_actions)) / @as(f32, @floatFromInt(infoset_count)) else 0.0});
    std.log.info("Actual memory usage: {d:.2} MB", .{@as(f32, @floatFromInt(total_memory)) / 1_048_576.0});
}

/// Save strategy to file
fn saveStrategy(trainer: *LinearCFRTrainer, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    
        // Use direct file I/O
    
    // Write header
    try file.writeAll("POKERSTRAT");
    try io_helpers.writeInt(file, u32, 1); // Version
    try io_helpers.writeInt(file, u32, @intCast(trainer.infoset_map.count()));
    
    // Write each information set
    var iter = trainer.infoset_map.iterator();
    while (iter.next()) |entry| {
        // Write key
        try io_helpers.writeInt(file, u64, entry.key_ptr.*);
        
        // Write data
        const data = entry.value_ptr;
        try io_helpers.writeInt(file, u32, @intCast(data.strategy.len));
        
        // Write average strategy
        const avg_strategy = data.getAverageStrategy();
        for (avg_strategy) |prob| {
            try file.writeAll(std.mem.asBytes(&prob));
        }
        
        // Write metadata
        try io_helpers.writeInt(file, u32, data.visits);
        try io_helpers.writeInt(file, u32, data.last_update);
    }
}

/// Load strategy from file
pub fn loadStrategy(allocator: std.mem.Allocator, path: []const u8) !LinearCFRTrainer {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    // Read and verify header
    var magic: [10]u8 = undefined;
    _ = try file.read(&magic);
    if (!std.mem.eql(u8, &magic, "POKERSTRAT")) {
        return error.InvalidStrategyFile;
    }
    
    const version = try io_helpers.readInt(file, u32);
    if (version != 1) {
        return error.UnsupportedVersion;
    }
    
    const num_infosets = try io_helpers.readInt(file, u32);
    
    // Create trainer
    var trainer = try LinearCFRTrainer.init(allocator, .{});
    
    // Read information sets
    for (0..num_infosets) |_| {
        const key = try io_helpers.readInt(file, u64);
        const num_actions = try io_helpers.readInt(file, u32);
        
        var data = try linear_cfr.InfoSetData.init(allocator, num_actions);
        
        // Read strategy
        for (data.strategy_sum) |*prob| {
            _ = try file.read(std.mem.asBytes(prob));
        }
        
        // Read metadata
        data.visits = try io_helpers.readInt(file, u32);
        data.last_update = try io_helpers.readInt(file, u32);
        
        try trainer.infoset_map.put(key, data);
    }
    
    return trainer;
}

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !TrainingConfig {
    var config = TrainingConfig{};
    
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    _ = args.next(); // Skip program name
    
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--iterations")) {
            if (args.next()) |value| {
                config.iterations = try std.fmt.parseInt(u32, value, 10);
            }
        } else if (std.mem.eql(u8, arg, "--threads")) {
            if (args.next()) |value| {
                config.threads = try std.fmt.parseInt(u32, value, 10);
            }
        } else if (std.mem.eql(u8, arg, "--players")) {
            if (args.next()) |value| {
                config.num_players = try std.fmt.parseInt(u8, value, 10);
            }
        } else if (std.mem.eql(u8, arg, "--output-dir")) {
            if (args.next()) |value| {
                config.output_dir = value;
            }
        } else if (std.mem.eql(u8, arg, "--no-linear-cfr")) {
            config.use_linear_cfr = false;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            config.print_progress = false;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
        }
    }
    
    return config;
}

fn printHelp() void {
    std.debug.print(
        \\Poker AI MCCFR Training
        \\
        \\Usage: train [options]
        \\
        \\Options:
        \\  --iterations <n>      Number of training iterations (default: 100000)
        \\  --threads <n>         Number of worker threads (default: 8)
        \\  --players <n>         Number of players (2-6, default: 2)
        \\  --output-dir <path>   Output directory for strategies (default: ./strategies)
        \\  --no-linear-cfr       Disable Linear CFR optimizations
        \\  --quiet               Disable progress output
        \\  --help                Show this help message
        \\
        \\Example:
        \\  train --iterations 1000000 --threads 16 --output-dir ./models
        \\
    , .{});
}

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    const config = try parseArgs(allocator);
    
    // Run training
    try trainMCCFR(config, allocator);
}

test "training config parsing" {
    const config = TrainingConfig{};
    try std.testing.expect(config.iterations == 100_000);
    try std.testing.expect(config.num_players == 2);
    try std.testing.expect(config.use_linear_cfr == true);
}

test "strategy save and load" {
    const allocator = std.testing.allocator;
    
    // Create a simple trainer
    var trainer = try LinearCFRTrainer.init(allocator, .{});
    defer trainer.deinit();
    
    // Save strategy
    const path = "test_strategy.strat";
    try saveStrategy(&trainer, path);
    defer std.fs.cwd().deleteFile(path) catch {};
    
    // Load strategy
    var loaded = try loadStrategy(allocator, path);
    defer loaded.deinit();
    
    // Verify
    try std.testing.expect(loaded.infoset_map.count() == trainer.infoset_map.count());
}
