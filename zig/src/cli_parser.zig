//! Command Line Interface Parser
//!
//! Comprehensive command-line argument parsing for poker AI
//! Features:
//! - Game mode selection (play/train/analyze)
//! - Player configuration (human/AI mix)
//! - Difficulty settings and AI parameters
//! - Training configuration
//! - Debug and logging options

const std = @import("std");

/// Game modes
pub const GameMode = enum {
    play, // Interactive play against AI
    train, // Train AI agents
    analyze, // Analyze hand histories or strategies
    demo, // Demonstration mode

    pub fn toString(self: GameMode) []const u8 {
        return switch (self) {
            .play => "play",
            .train => "train",
            .analyze => "analyze",
            .demo => "demo",
        };
    }

    pub fn fromString(str: []const u8) ?GameMode {
        if (std.mem.eql(u8, str, "play")) return .play;
        if (std.mem.eql(u8, str, "train")) return .train;
        if (std.mem.eql(u8, str, "analyze")) return .analyze;
        if (std.mem.eql(u8, str, "demo")) return .demo;
        return null;
    }
};

/// Player types
pub const PlayerType = enum {
    human,
    ai_weak,
    ai_medium,
    ai_strong,
    ai_expert,

    pub fn toString(self: PlayerType) []const u8 {
        return switch (self) {
            .human => "human",
            .ai_weak => "ai-weak",
            .ai_medium => "ai-medium",
            .ai_strong => "ai-strong",
            .ai_expert => "ai-expert",
        };
    }

    pub fn fromString(str: []const u8) ?PlayerType {
        if (std.mem.eql(u8, str, "human")) return .human;
        if (std.mem.eql(u8, str, "ai-weak")) return .ai_weak;
        if (std.mem.eql(u8, str, "ai-medium")) return .ai_medium;
        if (std.mem.eql(u8, str, "ai-strong")) return .ai_strong;
        if (std.mem.eql(u8, str, "ai-expert")) return .ai_expert;
        return null;
    }

    pub fn getDescription(self: PlayerType) []const u8 {
        return switch (self) {
            .human => "Human player",
            .ai_weak => "Weak AI (random play)",
            .ai_medium => "Medium AI (basic strategy)",
            .ai_strong => "Strong AI (advanced strategy)",
            .ai_expert => "Expert AI (MCCFR trained)",
        };
    }
};

/// Log levels
pub const LogLevel = enum {
    silent,
    error_only,
    warn,
    info,
    debug,
    verbose,

    pub fn fromString(str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, str, "silent")) return .silent;
        if (std.mem.eql(u8, str, "error")) return .error_only;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "verbose")) return .verbose;
        return null;
    }
};

/// Player configuration
pub const PlayerConfig = struct {
    type: PlayerType,
    name: []const u8,
    stack_size: u32,

    pub fn init(player_type: PlayerType, name: []const u8, stack_size: u32) PlayerConfig {
        return PlayerConfig{
            .type = player_type,
            .name = name,
            .stack_size = stack_size,
        };
    }
};

/// Training configuration
pub const TrainingConfig = struct {
    iterations: u32,
    checkpoint_interval: u32,
    output_dir: []const u8,
    resume_from: ?[]const u8,
    num_threads: u8,
    memory_limit_mb: u32,

    pub fn default() TrainingConfig {
        return TrainingConfig{
            .iterations = 10000,
            .checkpoint_interval = 1000,
            .output_dir = "trained_agents",
            .resume_from = null,
            .num_threads = 1,
            .memory_limit_mb = 4096,
        };
    }
};

/// Analysis configuration
pub const AnalysisConfig = struct {
    input_file: ?[]const u8,
    output_file: ?[]const u8,
    analysis_type: AnalysisType,

    pub const AnalysisType = enum {
        hand_history,
        strategy_profile,
        equity_calculation,
        exploitability,
    };

    pub fn default() AnalysisConfig {
        return AnalysisConfig{
            .input_file = null,
            .output_file = null,
            .analysis_type = .hand_history,
        };
    }
};

/// Complete configuration from command line
pub const Config = struct {
    // Mode and general settings
    game_mode: GameMode,
    log_level: LogLevel,
    no_color: bool,
    help: bool,
    version: bool,

    // Game settings
    num_players: u8,
    small_blind: u32,
    big_blind: u32,
    starting_stack: u32,
    max_hands: ?u32,

    // Players
    players: []PlayerConfig,

    // AI settings
    ai_think_time_ms: u32,
    ai_difficulty_variance: f32,

    // Training settings
    training: TrainingConfig,

    // Analysis settings
    analysis: AnalysisConfig,

    // Display settings
    display_mode: DisplayMode,
    animation_speed: u32,

    pub const DisplayMode = enum {
        compact,
        normal,
        detailed,

        pub fn fromString(str: []const u8) ?DisplayMode {
            if (std.mem.eql(u8, str, "compact")) return .compact;
            if (std.mem.eql(u8, str, "normal")) return .normal;
            if (std.mem.eql(u8, str, "detailed")) return .detailed;
            return null;
        }
    };

    pub fn default(allocator: std.mem.Allocator) !Config {
        var default_players = try allocator.alloc(PlayerConfig, 2);
        default_players[0] = PlayerConfig.init(.human, "Human", 1000);
        default_players[1] = PlayerConfig.init(.ai_medium, "AI", 1000);

        return Config{
            .game_mode = .play,
            .log_level = .info,
            .no_color = false,
            .help = false,
            .version = false,
            .num_players = 2,
            .small_blind = 10,
            .big_blind = 20,
            .starting_stack = 1000,
            .max_hands = null,
            .players = default_players,
            .ai_think_time_ms = 2000,
            .ai_difficulty_variance = 0.1,
            .training = TrainingConfig.default(),
            .analysis = AnalysisConfig.default(),
            .display_mode = .normal,
            .animation_speed = 500,
        };
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.players.len > 0) {
            allocator.free(self.players);
        }
    }
};

/// Command line parser
pub const CliParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CliParser {
        return CliParser{ .allocator = allocator };
    }

    /// Parse command line arguments
    pub fn parse(self: CliParser, args: []const []const u8) !Config {
        var config = try Config.default(self.allocator);

        var i: usize = 1; // Skip program name
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                config.help = true;
            } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
                config.version = true;
            } else if (std.mem.eql(u8, arg, "--mode") or std.mem.eql(u8, arg, "-m")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                if (GameMode.fromString(args[i])) |mode| {
                    config.game_mode = mode;
                } else {
                    return error.InvalidGameMode;
                }
            } else if (std.mem.eql(u8, arg, "--players") or std.mem.eql(u8, arg, "-p")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                const num = std.fmt.parseInt(u8, args[i], 10) catch return error.InvalidNumber;
                if (num < 2 or num > 8) return error.InvalidPlayerCount;
                config.num_players = num;
            } else if (std.mem.eql(u8, arg, "--small-blind")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.small_blind = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--big-blind")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.big_blind = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--stack")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.starting_stack = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--max-hands")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.max_hands = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--log-level")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                if (LogLevel.fromString(args[i])) |level| {
                    config.log_level = level;
                } else {
                    return error.InvalidLogLevel;
                }
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                config.no_color = true;
            } else if (std.mem.eql(u8, arg, "--display")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                if (Config.DisplayMode.fromString(args[i])) |mode| {
                    config.display_mode = mode;
                } else {
                    return error.InvalidDisplayMode;
                }
            } else if (std.mem.eql(u8, arg, "--ai-time")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.ai_think_time_ms = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--train-iterations")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.training.iterations = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--train-output")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.training.output_dir = args[i];
            } else if (std.mem.eql(u8, arg, "--train-resume")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.training.resume_from = args[i];
            } else if (std.mem.eql(u8, arg, "--threads")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                const threads = std.fmt.parseInt(u8, args[i], 10) catch return error.InvalidNumber;
                if (threads == 0 or threads > 64) return error.InvalidThreadCount;
                config.training.num_threads = threads;
            } else if (std.mem.eql(u8, arg, "--memory-limit")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                config.training.memory_limit_mb = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
            } else if (std.mem.eql(u8, arg, "--player-config")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                try self.parsePlayerConfig(args[i], &config);
            } else {
                // Unknown argument
                std.debug.print("Unknown argument: {s}\n", .{arg});
                return error.UnknownArgument;
            }
        }

        try self.validateConfig(&config);
        return config;
    }

    /// Parse player configuration string (format: "type:name:stack")
    fn parsePlayerConfig(self: CliParser, config_str: []const u8, config: *Config) !void {
        var parts = std.mem.splitScalar(u8, config_str, ':');

        const type_str = parts.next() orelse return error.InvalidPlayerConfig;
        const name_str = parts.next() orelse return error.InvalidPlayerConfig;
        const stack_str = parts.next() orelse return error.InvalidPlayerConfig;

        const player_type = PlayerType.fromString(type_str) orelse return error.InvalidPlayerType;
        const stack_size = std.fmt.parseInt(u32, stack_str, 10) catch return error.InvalidStackSize;

        // Reallocate players array to add new player
        const old_players = config.players;
        config.players = try self.allocator.alloc(PlayerConfig, old_players.len + 1);

        // Copy old players
        for (old_players, 0..) |player, i| {
            config.players[i] = player;
        }

        // Add new player
        config.players[old_players.len] = PlayerConfig.init(player_type, name_str, stack_size);

        // Free old array
        self.allocator.free(old_players);

        // Update player count
        config.num_players = @intCast(config.players.len);
    }

    /// Validate configuration
    fn validateConfig(self: CliParser, config: *Config) !void {
        _ = self; // Remove unused variable warning

        // Validate blinds
        if (config.big_blind <= config.small_blind) {
            return error.InvalidBlindStructure;
        }

        // Validate stack sizes
        if (config.starting_stack < config.big_blind * 10) {
            return error.StackTooSmall;
        }

        // Validate player count
        if (config.players.len != config.num_players) {
            return error.PlayerCountMismatch;
        }

        // Training mode specific validation
        if (config.game_mode == .train) {
            if (config.training.iterations == 0) {
                return error.InvalidTrainingIterations;
            }
        }
    }

    /// Print help message
    pub fn printHelp(program_name: []const u8) void {
        std.debug.print(
            \\Zig Poker AI - High-performance poker AI and game engine
            \\
            \\USAGE:
            \\    {s} [OPTIONS]
            \\
            \\OPTIONS:
            \\    -h, --help                 Show this help message
            \\    -v, --version              Show version information
            \\    -m, --mode <MODE>          Game mode: play, train, analyze, demo [default: play]
            \\    -p, --players <NUM>        Number of players (2-8) [default: 2]
            \\    --small-blind <AMOUNT>     Small blind amount [default: 10]
            \\    --big-blind <AMOUNT>       Big blind amount [default: 20]
            \\    --stack <AMOUNT>           Starting stack size [default: 1000]
            \\    --max-hands <NUM>          Maximum hands to play [default: unlimited]
            \\    --log-level <LEVEL>        Log level: silent, error, warn, info, debug, verbose [default: info]
            \\    --no-color                 Disable colored output
            \\    --display <MODE>           Display mode: compact, normal, detailed [default: normal]
            \\    --ai-time <MS>             AI thinking time in milliseconds [default: 2000]
            \\    --player-config <CONFIG>   Add player config (type:name:stack)
            \\
            \\TRAINING OPTIONS:
            \\    --train-iterations <NUM>   Number of training iterations [default: 10000]
            \\    --train-output <DIR>       Training output directory [default: trained_agents]
            \\    --train-resume <FILE>      Resume training from checkpoint
            \\    --threads <NUM>            Number of training threads [default: 1]
            \\    --memory-limit <MB>        Memory limit in MB [default: 4096]
            \\
            \\EXAMPLES:
            \\    {s} --mode play --players 4 --display detailed
            \\    {s} --mode train --train-iterations 50000 --threads 4
            \\    {s} --player-config human:Alice:1500 --player-config ai-strong:Bob:1000
            \\    {s} --mode analyze --log-level debug
            \\
            \\PLAYER TYPES:
            \\    human      - Human player (interactive)
            \\    ai-weak    - Weak AI (random play)
            \\    ai-medium  - Medium AI (basic strategy)
            \\    ai-strong  - Strong AI (advanced strategy)
            \\    ai-expert  - Expert AI (MCCFR trained)
            \\
        , .{ program_name, program_name, program_name, program_name, program_name });
    }

    /// Print version information
    pub fn printVersion() void {
        const version = @import("main.zig").version;
        std.debug.print("Zig Poker AI v{d}.{d}.{d}\n", .{ version.major, version.minor, version.patch });
        std.debug.print("High-performance poker AI implementation in Zig\n");
        std.debug.print("Built with Zig {s}\n", .{@import("builtin").zig_version_string});
    }
};

/// Parse arguments from process.args()
pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = CliParser.init(allocator);
    return parser.parse(args);
}

// Unit tests
test "game mode parsing" {
    const testing = std.testing;

    try testing.expectEqual(GameMode.play, GameMode.fromString("play").?);
    try testing.expectEqual(GameMode.train, GameMode.fromString("train").?);
    try testing.expectEqual(@as(?GameMode, null), GameMode.fromString("invalid"));
}

test "player type parsing" {
    const testing = std.testing;

    try testing.expectEqual(PlayerType.human, PlayerType.fromString("human").?);
    try testing.expectEqual(PlayerType.ai_strong, PlayerType.fromString("ai-strong").?);
    try testing.expectEqual(@as(?PlayerType, null), PlayerType.fromString("invalid"));
}

test "basic argument parsing" {
    const testing = std.testing;

    var parser = CliParser.init(testing.allocator);

    const args = [_][]const u8{ "poker_ai", "--mode", "train", "--players", "4" };
    var config = try parser.parse(&args);
    defer config.deinit(testing.allocator);

    try testing.expectEqual(GameMode.train, config.game_mode);
    try testing.expectEqual(@as(u8, 4), config.num_players);
}

test "config validation" {
    const testing = std.testing;

    var parser = CliParser.init(testing.allocator);

    // Test invalid blind structure
    const invalid_args = [_][]const u8{ "poker_ai", "--small-blind", "50", "--big-blind", "25" };
    try testing.expectError(error.InvalidBlindStructure, parser.parse(&invalid_args));
}

test "default configuration" {
    const testing = std.testing;

    var config = try Config.default(testing.allocator);
    defer config.deinit(testing.allocator);

    try testing.expectEqual(GameMode.play, config.game_mode);
    try testing.expectEqual(@as(u8, 2), config.num_players);
    try testing.expectEqual(@as(u32, 20), config.big_blind);
    try testing.expectEqual(@as(usize, 2), config.players.len);
}
