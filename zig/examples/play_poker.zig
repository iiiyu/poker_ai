//! Interactive Poker Game
//!
//! Main entry point for playing poker against AI opponents
//! Features:
//! - Interactive terminal UI with full gameplay
//! - Multiple AI difficulty levels 
//! - Customizable game settings
//! - Statistics tracking
//! - Settings persistence
//!
//! Usage:
//! zig run examples/play_poker.zig -- --help
//! zig run examples/play_poker.zig -- --players 3 --starting-stack 1000

const std = @import("std");
const poker_ai = @import("poker_ai");
const terminal_ui = poker_ai.terminal_ui;
const cli_parser = poker_ai.cli_parser;
const ascii_cards = poker_ai.ascii_cards;

const Colors = ascii_cards.Colors;

/// Print welcome banner
fn printWelcomeBanner() void {
    const banner =
        \\
        \\  ██████╗  ██████╗ ██╗  ██╗███████╗██████╗      █████╗ ██╗
        \\  ██╔══██╗██╔═══██╗██║ ██╔╝██╔════╝██╔══██╗    ██╔══██╗██║
        \\  ██████╔╝██║   ██║█████╔╝ █████╗  ██████╔╝    ███████║██║
        \\  ██╔═══╝ ██║   ██║██╔═██╗ ██╔══╝  ██╔══██╗    ██╔══██║██║
        \\  ██║     ╚██████╔╝██║  ██╗███████╗██║  ██║    ██║  ██║██║
        \\  ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝
        \\
        \\                    Texas Hold'em Poker AI
        \\                        Version 0.1.0
        \\
    ;
    
    std.debug.print("{s}{s}{s}\n", .{ Colors.WHITE, banner, Colors.RESET });
}

/// Print usage information
fn printUsage(program_name: []const u8) void {
    std.debug.print("Usage: {s} [options]\n\n", .{program_name});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --help                    Show this help message\n", .{});
    std.debug.print("  --version                 Show version information\n", .{});
    std.debug.print("  --players <n>             Number of players (2-6, default: 3)\n", .{});
    std.debug.print("  --starting-stack <n>      Starting chip stack (default: 1000)\n", .{});
    std.debug.print("  --small-blind <n>         Small blind amount (default: 10)\n", .{});
    std.debug.print("  --big-blind <n>           Big blind amount (default: 20)\n", .{});
    std.debug.print("  --max-hands <n>           Maximum hands to play (default: unlimited)\n", .{});
    std.debug.print("  --ai-think-time <ms>      AI thinking time in ms (default: 800)\n", .{});
    std.debug.print("  --display-mode <mode>     Display mode: compact/normal/detailed (default: normal)\n", .{});
    std.debug.print("  --no-color                Disable colored output\n", .{});
    std.debug.print("  --difficulty <level>      AI difficulty: weak/medium/strong/expert (default: medium)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  {s}                                    # Start with default settings\n", .{program_name});
    std.debug.print("  {s} --players 4 --starting-stack 2000  # 4 players with 2000 chips each\n", .{program_name});
    std.debug.print("  {s} --difficulty mccfr --max-hands 50  # Use MCCFR AI for 50 hands\n", .{program_name});
    std.debug.print("  {s} --no-color --display-mode compact  # Minimal UI without colors\n", .{program_name});
}

/// Create default configuration for interactive play
fn createDefaultConfig(allocator: std.mem.Allocator) !cli_parser.Config {
    const num_players: u8 = 3;
    const starting_stack: u32 = 1000;
    
    // Allocate players array
    var players = try allocator.alloc(cli_parser.PlayerConfig, num_players);
    
    // Configure players: Human player + AI opponents
    // Note: Using string literals for names - no allocation needed
    players[0] = cli_parser.PlayerConfig{
        .type = .human,
        .name = "Human",
        .stack_size = starting_stack,
    };
    
    for (1..num_players) |i| {
        players[i] = cli_parser.PlayerConfig{
            .type = .ai_medium,
            .name = if (i == 1) "AI 1" else "AI 2",
            .stack_size = starting_stack,
        };
    }
    
    // Create config without calling Config.default()
    return cli_parser.Config{
        .game_mode = .play,
        .log_level = .info,
        .no_color = false,
        .help = false,
        .version = false,
        .num_players = num_players,
        .small_blind = 10,
        .big_blind = 20,
        .starting_stack = starting_stack,
        .max_hands = null,
        .players = players,
        .ai_think_time_ms = 800,
        .ai_difficulty_variance = 0.1,
        .training = cli_parser.TrainingConfig.default(),
        .analysis = cli_parser.AnalysisConfig.default(),
        .display_mode = .normal,
        .animation_speed = 500,
    };
}

/// Parse command line arguments with enhanced error handling
fn parseCommandLineArgs(allocator: std.mem.Allocator) !?cli_parser.Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    const program_name = args.next() orelse "play_poker";
    
    var config = try createDefaultConfig(allocator);
    
    // Parse command line arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(program_name);
            return null;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            std.debug.print("Poker AI Terminal Interface v0.1.0\n", .{});
            return null;
        } else if (std.mem.eql(u8, arg, "--players")) {
            const value = args.next() orelse {
                std.debug.print("Error: --players requires a value\n", .{});
                return error.MissingArgument;
            };
            const new_player_count = std.fmt.parseInt(u8, value, 10) catch {
                std.debug.print("Error: Invalid player count '{s}'\n", .{value});
                return error.InvalidNumber;
            };
            if (new_player_count < 2 or new_player_count > 6) {
                std.debug.print("Error: Player count must be between 2 and 6\n", .{});
                return error.InvalidPlayerCount;
            }
            
            // If player count changed, reallocate players array
            if (new_player_count != config.num_players) {
                // Free old players array (no need to free names since they're string literals)
                allocator.free(config.players);
                
                config.num_players = new_player_count;
                
                // Allocate new players array
                config.players = try allocator.alloc(cli_parser.PlayerConfig, config.num_players);
                
                // Re-initialize players with string literal names
                config.players[0] = cli_parser.PlayerConfig{
                    .type = .human,
                    .name = "Human",
                    .stack_size = config.starting_stack,
                };
                
                // Use static AI names
                const ai_names = [_][]const u8{ "AI 1", "AI 2", "AI 3", "AI 4", "AI 5" };
                for (1..config.num_players) |i| {
                    config.players[i] = cli_parser.PlayerConfig{
                        .type = .ai_medium,
                        .name = if (i - 1 < ai_names.len) ai_names[i - 1] else "AI",
                        .stack_size = config.starting_stack,
                    };
                }
            }
        } else if (std.mem.eql(u8, arg, "--starting-stack")) {
            const value = args.next() orelse {
                std.debug.print("Error: --starting-stack requires a value\n", .{});
                return error.MissingArgument;
            };
            config.starting_stack = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("Error: Invalid starting stack '{s}'\n", .{value});
                return error.InvalidNumber;
            };
        } else if (std.mem.eql(u8, arg, "--small-blind")) {
            const value = args.next() orelse {
                std.debug.print("Error: --small-blind requires a value\n", .{});
                return error.MissingArgument;
            };
            config.small_blind = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("Error: Invalid small blind '{s}'\n", .{value});
                return error.InvalidNumber;
            };
        } else if (std.mem.eql(u8, arg, "--big-blind")) {
            const value = args.next() orelse {
                std.debug.print("Error: --big-blind requires a value\n", .{});
                return error.MissingArgument;
            };
            config.big_blind = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("Error: Invalid big blind '{s}'\n", .{value});
                return error.InvalidNumber;
            };
        } else if (std.mem.eql(u8, arg, "--max-hands")) {
            const value = args.next() orelse {
                std.debug.print("Error: --max-hands requires a value\n", .{});
                return error.MissingArgument;
            };
            const hands = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("Error: Invalid max hands '{s}'\n", .{value});
                return error.InvalidNumber;
            };
            config.max_hands = hands;
        } else if (std.mem.eql(u8, arg, "--ai-think-time")) {
            const value = args.next() orelse {
                std.debug.print("Error: --ai-think-time requires a value\n", .{});
                return error.MissingArgument;
            };
            config.ai_think_time_ms = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("Error: Invalid AI think time '{s}'\n", .{value});
                return error.InvalidNumber;
            };
        } else if (std.mem.eql(u8, arg, "--display-mode")) {
            const value = args.next() orelse {
                std.debug.print("Error: --display-mode requires a value\n", .{});
                return error.MissingArgument;
            };
            if (std.mem.eql(u8, value, "compact")) {
                config.display_mode = .compact;
            } else if (std.mem.eql(u8, value, "normal")) {
                config.display_mode = .normal;
            } else if (std.mem.eql(u8, value, "detailed")) {
                config.display_mode = .detailed;
            } else {
                std.debug.print("Error: Invalid display mode '{s}'. Use compact/normal/detailed\n", .{value});
                return error.InvalidDisplayMode;
            }
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            config.no_color = true;
        } else if (std.mem.eql(u8, arg, "--difficulty")) {
            const value = args.next() orelse {
                std.debug.print("Error: --difficulty requires a value\n", .{});
                return error.MissingArgument;
            };
            
            const ai_type: cli_parser.PlayerType = if (std.mem.eql(u8, value, "weak"))
                .ai_weak
            else if (std.mem.eql(u8, value, "medium"))
                .ai_medium
            else if (std.mem.eql(u8, value, "strong"))
                .ai_strong
            else if (std.mem.eql(u8, value, "expert"))
                .ai_expert
            else {
                std.debug.print("Error: Invalid difficulty '{s}'. Use weak/medium/strong/expert\n", .{value});
                return error.InvalidPlayerType;
            };
            
            // Update AI players with new type
            for (1..config.num_players) |i| {
                if (i < config.players.len) {
                    config.players[i].type = ai_type;
                }
            }
        } else {
            std.debug.print("Error: Unknown argument '{s}'\n", .{arg});
            std.debug.print("Use --help for usage information.\n", .{});
            return error.UnknownArgument;
        }
    }
    
    // Validation
    if (config.big_blind <= config.small_blind) {
        std.debug.print("Error: Big blind must be greater than small blind\n", .{});
        return error.InvalidBlindStructure;
    }
    
    if (config.starting_stack < config.big_blind * 20) {
        std.debug.print("Warning: Starting stack is very small compared to blinds\n", .{});
        std.debug.print("Recommended minimum: {d} chips\n", .{config.big_blind * 20});
    }
    
    return config;
}

/// Main entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    const config = parseCommandLineArgs(allocator) catch {
        std.process.exit(1);
    } orelse {
        // Help or version was displayed
        return;
    };
    
    // TODO: Fix memory management - defer config.deinit(allocator) causes segfault
    // defer config.deinit(allocator);
    
    // Print welcome banner
    if (!config.no_color) {
        printWelcomeBanner();
    } else {
        std.debug.print("\nPoker AI - Texas Hold'em Terminal Interface v0.1.0\n\n", .{});
    }
    
    // Display game configuration
    std.debug.print("Game Configuration:\n", .{});
    std.debug.print("  Players: {d} ({d} AI opponents + You)\n", .{ config.num_players, config.num_players - 1 });
    std.debug.print("  Starting Stack: ${d}\n", .{config.starting_stack});
    std.debug.print("  Blinds: ${d}/${d}\n", .{ config.small_blind, config.big_blind });
    if (config.max_hands) |max_hands| {
        std.debug.print("  Max Hands: {d}\n", .{max_hands});
    } else {
        std.debug.print("  Max Hands: Unlimited\n", .{});
    }
    std.debug.print("  AI Difficulty: {s}\n", .{@tagName(config.players[1].type)});
    std.debug.print("  Display Mode: {s}\n", .{@tagName(config.display_mode)});
    std.debug.print("\n", .{});
    
    // Instructions
    if (!config.no_color) {
        std.debug.print("{s}Instructions:{s}\n", .{ Colors.BOLD, Colors.RESET });
        std.debug.print("  • Use {s}W/S{s} or {s}↑/↓{s} to navigate menus\n", .{ Colors.WHITE, Colors.RESET, Colors.WHITE, Colors.RESET });
        std.debug.print("  • Press {s}Enter{s} to select actions\n", .{ Colors.WHITE, Colors.RESET });
        std.debug.print("  • Press {s}Q{s} to quit at any time\n", .{ Colors.WHITE, Colors.RESET });
        std.debug.print("  • Use {s}+/-{s} to adjust raise amounts\n", .{ Colors.WHITE, Colors.RESET });
    } else {
        std.debug.print("Instructions:\n", .{});
        std.debug.print("  • Use W/S or ↑/↓ to navigate menus\n", .{});
        std.debug.print("  • Press Enter to select actions\n", .{});
        std.debug.print("  • Press Q to quit at any time\n", .{});
        std.debug.print("  • Use +/- to adjust raise amounts\n", .{});
    }
    std.debug.print("\nStarting game...\n", .{});
    
    // Start the terminal UI
    try terminal_ui.runTerminalUI(allocator, config);
    
    // Farewell message
    if (!config.no_color) {
        std.debug.print("\n{s}Thanks for playing Poker AI!{s}\n", .{ Colors.WHITE, Colors.RESET });
    } else {
        std.debug.print("\nThanks for playing Poker AI!\n", .{});
    }
}

// Unit tests
test "argument parsing" {
    const testing = std.testing;
    
    // Test basic functionality (without actual args parsing)
    var config = try createDefaultConfig(testing.allocator);
    defer config.deinit(testing.allocator);
    
    try testing.expectEqual(@as(u8, 3), config.num_players);
    try testing.expectEqual(@as(u32, 1000), config.starting_stack);
    try testing.expectEqual(cli_parser.GameMode.play, config.game_mode);
    try testing.expectEqual(cli_parser.PlayerType.human, config.players[0].type);
    try testing.expectEqual(cli_parser.PlayerType.simple_ai, config.players[1].type);
}

test "config validation" {
    const testing = std.testing;
    
    var config = try createDefaultConfig(testing.allocator);
    defer config.deinit(testing.allocator);
    
    // Valid configuration should not cause issues
    try testing.expect(config.big_blind > config.small_blind);
    try testing.expect(config.starting_stack > config.big_blind);
}