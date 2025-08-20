//! Terminal UI Framework
//! 
//! Main terminal interface for poker AI with complete game management
//! Features:
//! - Interactive menu system for game modes and settings
//! - Complete game loop with human and AI players
//! - Settings configuration and persistence
//! - Game statistics and session management
//! - Error handling and graceful shutdown

const std = @import("std");
const ascii_cards = @import("ascii_cards.zig");
const game_display = @import("game_display.zig");
const input_handler = @import("input_handler.zig");
const cli_parser = @import("cli_parser.zig");
const game_engine = @import("game_engine.zig");
const player = @import("player.zig");

const Colors = ascii_cards.Colors;
const GameDisplay = game_display.GameDisplay;
const InputHandler = input_handler.InputHandler;
const Config = cli_parser.Config;
const PlayerConfig = cli_parser.PlayerConfig;
const Player = player.Player;
const TexasHoldemGameEngine = game_engine.TexasHoldemGameEngine;
const BettingStage = game_engine.BettingStage;

/// Menu items for main menu
pub const MainMenuItem = enum {
    play_game,
    train_ai,
    analyze_hands,
    settings,
    view_stats,
    quit,
    
    pub fn toString(self: MainMenuItem) []const u8 {
        return switch (self) {
            .play_game => "Play Game",
            .train_ai => "Train AI",
            .analyze_hands => "Analyze Hands",
            .settings => "Settings",
            .view_stats => "View Statistics",
            .quit => "Quit",
        };
    }
};

/// Settings menu items
pub const SettingsMenuItem = enum {
    display_mode,
    sound_effects,
    ai_difficulty,
    betting_structure,
    player_names,
    save_settings,
    back,
    
    pub fn toString(self: SettingsMenuItem) []const u8 {
        return switch (self) {
            .display_mode => "Display Mode",
            .sound_effects => "Sound Effects",
            .ai_difficulty => "AI Difficulty",
            .betting_structure => "Betting Structure",
            .player_names => "Player Names",
            .save_settings => "Save Settings",
            .back => "Back to Main Menu",
        };
    }
};

/// Game session statistics
pub const GameStats = struct {
    hands_played: u32,
    hands_won: u32,
    total_winnings: i32,
    biggest_pot_won: u32,
    session_start_time: i64,
    
    pub fn init() GameStats {
        return GameStats{
            .hands_played = 0,
            .hands_won = 0,
            .total_winnings = 0,
            .biggest_pot_won = 0,
            .session_start_time = std.time.timestamp(),
        };
    }
    
    pub fn getWinRate(self: GameStats) f32 {
        if (self.hands_played == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hands_won)) / @as(f32, @floatFromInt(self.hands_played));
    }
    
    pub fn getSessionDuration(self: GameStats) i64 {
        return std.time.timestamp() - self.session_start_time;
    }
};

/// Terminal UI state
pub const TerminalUI = struct {
    allocator: std.mem.Allocator,
    config: Config,
    display: GameDisplay,
    input: InputHandler,
    stats: GameStats,
    is_running: bool,
    current_menu: MenuState,
    
    const MenuState = enum {
        main_menu,
        settings_menu,
        in_game,
        training,
        analysis,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) !TerminalUI {
        const display = GameDisplay.init(allocator, 120, 40, config.display_mode, !config.no_color);
        const input = InputHandler.init(allocator);
        
        return TerminalUI{
            .allocator = allocator,
            .config = config,
            .display = display,
            .input = input,
            .stats = GameStats.init(),
            .is_running = true,
            .current_menu = .main_menu,
        };
    }
    
    pub fn deinit(self: *TerminalUI) void {
        self.display.deinit();
        self.input.deinit();
        self.config.deinit(self.allocator);
    }
    
    /// Main event loop
    pub fn run(self: *TerminalUI) !void {
        try self.input.enableRawMode();
        defer self.input.restoreMode() catch {};
        
        ascii_cards.Screen.hideCursor();
        defer ascii_cards.Screen.showCursor();
        
        while (self.is_running) {
            switch (self.current_menu) {
                .main_menu => try self.handleMainMenu(),
                .settings_menu => try self.handleSettingsMenu(),
                .in_game => try self.handleGame(),
                .training => try self.handleTraining(),
                .analysis => try self.handleAnalysis(),
            }
            
            // Small delay to prevent busy waiting
            std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
        }
    }
    
    /// Handle main menu navigation
    fn handleMainMenu(self: *TerminalUI) !void {
        const menu_items = [_]MainMenuItem{ 
            .play_game, .train_ai, .analyze_hands, .settings, .view_stats, .quit 
        };
        
        var selected_index: usize = 0;
        
        while (self.current_menu == .main_menu and self.is_running) {
            try self.drawMainMenu(menu_items[0..], selected_index);
            
            const input_event = try self.input.handleMenu(
                &[_][]const u8{
                    menu_items[0].toString(),
                    menu_items[1].toString(),
                    menu_items[2].toString(),
                    menu_items[3].toString(),
                    menu_items[4].toString(),
                    menu_items[5].toString(),
                },
                &selected_index,
                null
            );
            
            switch (input_event) {
                .menu_action => |action| {
                    switch (action) {
                        .select => {
                            switch (menu_items[selected_index]) {
                                .play_game => self.current_menu = .in_game,
                                .train_ai => self.current_menu = .training,
                                .analyze_hands => self.current_menu = .analysis,
                                .settings => self.current_menu = .settings_menu,
                                .view_stats => try self.showStatistics(),
                                .quit => self.is_running = false,
                            }
                        },
                        .quit => self.is_running = false,
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    
    /// Draw main menu
    fn drawMainMenu(self: *TerminalUI, items: []const MainMenuItem, selected: usize) !void {
        ascii_cards.Screen.clear();
        
        // Title
        const title_y = 5;
        const center_x = self.display.layout.center_x;
        
        self.moveCursor(title_y, center_x - 15);
        if (self.display.use_color) {
            std.debug.print("{s}╔═══════════════════════════════╗{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("╔═══════════════════════════════╗");
        }
        
        self.moveCursor(title_y + 1, center_x - 15);
        if (self.display.use_color) {
            std.debug.print("{s}║      ZIG POKER AI v0.1.0      ║{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("║      ZIG POKER AI v0.1.0      ║");
        }
        
        self.moveCursor(title_y + 2, center_x - 15);
        if (self.display.use_color) {
            std.debug.print("{s}╚═══════════════════════════════╝{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("╚═══════════════════════════════╝");
        }
        
        // Menu items
        const menu_start_y = title_y + 5;
        
        for (items, 0..) |item, i| {
            const y = menu_start_y + @as(u16, @intCast(i * 2));
            self.moveCursor(y, center_x - 10);
            
            if (i == selected) {
                if (self.display.use_color) {
                    std.debug.print("{s}>>> {s} <<<{s}", .{ Colors.BOLD, item.toString(), Colors.RESET });
                } else {
                    std.debug.print(">>> {s} <<<", .{item.toString()});
                }
            } else {
                std.debug.print("    {s}", .{item.toString()});
            }
        }
        
        // Instructions
        const instr_y = menu_start_y + @as(u16, @intCast(items.len * 2)) + 3;
        self.moveCursor(instr_y, center_x - 20);
        if (self.display.use_color) {
            std.debug.print("{s}Use W/S or ↑/↓ to navigate, Enter to select, Q to quit{s}", .{ Colors.DIM, Colors.RESET });
        } else {
            std.debug.print("Use W/S or ↑/↓ to navigate, Enter to select, Q to quit");
        }
    }
    
    /// Handle settings menu
    fn handleSettingsMenu(self: *TerminalUI) !void {
        const menu_items = [_]SettingsMenuItem{
            .display_mode, .sound_effects, .ai_difficulty, .betting_structure, .player_names, .save_settings, .back
        };
        
        var selected_index: usize = 0;
        
        while (self.current_menu == .settings_menu and self.is_running) {
            try self.drawSettingsMenu(menu_items[0..], selected_index);
            
            const input_event = try self.input.handleMenu(
                &[_][]const u8{
                    menu_items[0].toString(),
                    menu_items[1].toString(),
                    menu_items[2].toString(),
                    menu_items[3].toString(),
                    menu_items[4].toString(),
                    menu_items[5].toString(),
                    menu_items[6].toString(),
                },
                &selected_index,
                null
            );
            
            switch (input_event) {
                .menu_action => |action| {
                    switch (action) {
                        .select => {
                            switch (menu_items[selected_index]) {
                                .display_mode => try self.changeDisplayMode(),
                                .sound_effects => {}, // TODO: Implement sound settings
                                .ai_difficulty => try self.changeAIDifficulty(),
                                .betting_structure => try self.changeBettingStructure(),
                                .player_names => try self.changePlayerNames(),
                                .save_settings => try self.saveSettings(),
                                .back => self.current_menu = .main_menu,
                            }
                        },
                        .back, .quit => self.current_menu = .main_menu,
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    
    /// Draw settings menu
    fn drawSettingsMenu(self: *TerminalUI, items: []const SettingsMenuItem, selected: usize) !void {
        ascii_cards.Screen.clear();
        
        // Title
        const title_y = 3;
        const center_x = self.display.layout.center_x;
        
        self.moveCursor(title_y, center_x - 10);
        if (self.display.use_color) {
            std.debug.print("{s}SETTINGS{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("SETTINGS");
        }
        
        // Current settings display
        const settings_y = title_y + 3;
        self.moveCursor(settings_y, 5);
        std.debug.print("Current Settings:");
        
        self.moveCursor(settings_y + 1, 5);
        std.debug.print("Display Mode: {s}", .{@tagName(self.config.display_mode)});
        
        self.moveCursor(settings_y + 2, 5);
        std.debug.print("Players: {d}", .{self.config.num_players});
        
        self.moveCursor(settings_y + 3, 5);
        std.debug.print("Blinds: {d}/{d}", .{ self.config.small_blind, self.config.big_blind });
        
        // Menu items
        const menu_start_y = settings_y + 6;
        
        for (items, 0..) |item, i| {
            const y = menu_start_y + @as(u16, @intCast(i));
            self.moveCursor(y, center_x - 15);
            
            if (i == selected) {
                if (self.display.use_color) {
                    std.debug.print("{s}> {s}{s}", .{ Colors.BOLD, item.toString(), Colors.RESET });
                } else {
                    std.debug.print("> {s}", .{item.toString()});
                }
            } else {
                std.debug.print("  {s}", .{item.toString()});
            }
        }
    }
    
    /// Handle main game loop
    fn handleGame(self: *TerminalUI) !void {
        // Initialize game
        var game_config = game_engine.GameConfig{
            .num_players = self.config.num_players,
            .small_blind = self.config.small_blind,
            .big_blind = self.config.big_blind,
            .starting_stack = self.config.starting_stack,
            .ante = 0,
        };
        
        var game = try TexasHoldemGameEngine.init(self.allocator, game_config);
        defer game.deinit();
        
        // Initialize players from config
        for (self.config.players, 0..) |player_config, i| {
            const player_id = @as(u8, @intCast(i));
            const game_player = Player.init(player_id, player_config.stack_size);
            game.players[i] = game_player;
        }
        
        self.display.clearActionHistory();
        
        var hand_count: u32 = 0;
        
        while (self.current_menu == .in_game and self.is_running) {
            // Check if we should quit due to max hands
            if (self.config.max_hands) |max| {
                if (hand_count >= max) break;
            }
            
            // Start new hand
            try game.newHand();
            hand_count += 1;
            self.stats.hands_played += 1;
            
            // Game loop for this hand
            while (!game.isTerminal()) {
                // Render current game state
                try self.display.render(
                    game.players[0..game.config.num_players],
                    game.community_cards[0..@intFromEnum(game.betting_stage.boardSize())],
                    game.pot.getTotalAmount(),
                    game.current_bet,
                    game.betting_stage,
                    game.dealer_position,
                    if (game.current_player_index < game.config.num_players) game.current_player_index else null
                );
                
                // Handle current player's action
                if (game.current_player_index < game.config.num_players) {
                    const current_player = &game.players[game.current_player_index];
                    const player_config = self.config.players[game.current_player_index];
                    
                    if (player_config.type == .human) {
                        // Human player
                        try self.handleHumanPlayerAction(current_player, &game);
                    } else {
                        // AI player
                        try self.handleAIPlayerAction(current_player, &game, player_config.type);
                    }
                }
                
                // Check for quit input
                if (try self.input.checkForQuit()) {
                    self.current_menu = .main_menu;
                    break;
                }
            }
            
            // Show hand result if game completed normally
            if (game.isTerminal() and self.current_menu == .in_game) {
                try self.showHandResult(&game);
                try self.input.waitForAnyKey("Press any key for next hand...");
            }
        }
    }
    
    /// Handle human player action
    fn handleHumanPlayerAction(self: *TerminalUI, current_player: *Player, game: *TexasHoldemGameEngine) !void {
        _ = game; // Remove unused variable warning for now
        _ = current_player; // Remove unused variable warning for now
        
        // TODO: Implement human player action logic
        // This would involve:
        // 1. Determine available actions based on game state
        // 2. Get player input using input handler
        // 3. Validate and execute the action
        // 4. Update display and action history
        
        // For now, just wait for any input to continue
        try self.input.waitForAnyKey("Human player turn (press any key)...");
    }
    
    /// Handle AI player action
    fn handleAIPlayerAction(
        self: *TerminalUI, 
        current_player: *Player, 
        game: *TexasHoldemGameEngine, 
        ai_type: cli_parser.PlayerType
    ) !void {
        _ = current_player; // Remove unused variable warning for now
        _ = game; // Remove unused variable warning for now
        _ = ai_type; // Remove unused variable warning for now
        
        // TODO: Implement AI player action logic
        // This would involve:
        // 1. Determine available actions
        // 2. Use appropriate AI strategy based on ai_type
        // 3. Execute the action
        // 4. Add thinking delay based on config.ai_think_time_ms
        // 5. Update display and action history
        
        // Simulate thinking time
        std.time.sleep(@as(u64, self.config.ai_think_time_ms) * std.time.ns_per_ms);
    }
    
    /// Show hand result
    fn showHandResult(self: *TerminalUI, game: *TexasHoldemGameEngine) !void {
        // TODO: Implement hand result display
        // This would involve:
        // 1. Determine winner(s) and hand rankings
        // 2. Calculate pot distribution
        // 3. Update statistics
        // 4. Show result screen with all player cards
        
        _ = game; // Remove unused variable warning for now
        
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Hand completed! (Result display not yet implemented)");
    }
    
    /// Handle training mode
    fn handleTraining(self: *TerminalUI) !void {
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Training mode not yet implemented.");
        self.moveCursor(12, 40);
        std.debug.print("Press any key to return to main menu...");
        
        try self.input.waitForAnyKey(null);
        self.current_menu = .main_menu;
    }
    
    /// Handle analysis mode  
    fn handleAnalysis(self: *TerminalUI) !void {
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Analysis mode not yet implemented.");
        self.moveCursor(12, 40);
        std.debug.print("Press any key to return to main menu...");
        
        try self.input.waitForAnyKey(null);
        self.current_menu = .main_menu;
    }
    
    /// Show statistics
    fn showStatistics(self: *TerminalUI) !void {
        ascii_cards.Screen.clear();
        
        const center_x = self.display.layout.center_x;
        var y: u16 = 5;
        
        // Title
        self.moveCursor(y, center_x - 10);
        if (self.display.use_color) {
            std.debug.print("{s}SESSION STATISTICS{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("SESSION STATISTICS");
        }
        y += 3;
        
        // Stats
        self.moveCursor(y, center_x - 15);
        std.debug.print("Hands Played: {d}", .{self.stats.hands_played});
        y += 1;
        
        self.moveCursor(y, center_x - 15);
        std.debug.print("Hands Won: {d}", .{self.stats.hands_won});
        y += 1;
        
        self.moveCursor(y, center_x - 15);
        std.debug.print("Win Rate: {d:.1}%", .{self.stats.getWinRate() * 100});
        y += 1;
        
        self.moveCursor(y, center_x - 15);
        std.debug.print("Total Winnings: ${d}", .{self.stats.total_winnings});
        y += 1;
        
        self.moveCursor(y, center_x - 15);
        std.debug.print("Biggest Pot: ${d}", .{self.stats.biggest_pot_won});
        y += 1;
        
        self.moveCursor(y, center_x - 15);
        const duration = self.stats.getSessionDuration();
        const hours = @divTrunc(duration, 3600);
        const minutes = @divTrunc(@mod(duration, 3600), 60);
        std.debug.print("Session Time: {d}h {d}m", .{ hours, minutes });
        y += 3;
        
        self.moveCursor(y, center_x - 15);
        std.debug.print("Press any key to return to main menu...");
        
        try self.input.waitForAnyKey(null);
    }
    
    /// Settings change functions
    fn changeDisplayMode(self: *TerminalUI) !void {
        const modes = [_]ascii_cards.DisplayMode{ .compact, .normal, .detailed };
        const mode_names = [_][]const u8{ "Compact", "Normal", "Detailed" };
        
        var selected: usize = switch (self.config.display_mode) {
            .compact => 0,
            .normal => 1,
            .detailed => 2,
        };
        
        // Simple cycling through modes for now
        selected = (selected + 1) % modes.len;
        self.config.display_mode = modes[selected];
        self.display.display_mode = modes[selected];
        
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Display mode changed to: {s}", .{mode_names[selected]});
        self.moveCursor(12, 40);
        std.debug.print("Press any key to continue...");
        
        try self.input.waitForAnyKey(null);
    }
    
    fn changeAIDifficulty(self: *TerminalUI) !void {
        // TODO: Implement AI difficulty change
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("AI difficulty change not yet implemented.");
        try self.input.waitForAnyKey("Press any key to continue...");
    }
    
    fn changeBettingStructure(self: *TerminalUI) !void {
        // TODO: Implement betting structure change
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Betting structure change not yet implemented.");
        try self.input.waitForAnyKey("Press any key to continue...");
    }
    
    fn changePlayerNames(self: *TerminalUI) !void {
        // TODO: Implement player name change
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Player name change not yet implemented.");
        try self.input.waitForAnyKey("Press any key to continue...");
    }
    
    fn saveSettings(self: *TerminalUI) !void {
        // TODO: Implement settings save to file
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Settings saved successfully!");
        try self.input.waitForAnyKey("Press any key to continue...");
    }
    
    /// Helper to move cursor
    fn moveCursor(self: *TerminalUI, row: u16, col: u16) void {
        _ = self; // Remove unused variable warning
        ascii_cards.Screen.moveTo(row, col);
    }
};

/// Main entry point for terminal UI
pub fn runTerminalUI(allocator: std.mem.Allocator, config: Config) !void {
    var ui = try TerminalUI.init(allocator, config);
    defer ui.deinit();
    
    try ui.run();
}

/// Create terminal UI from command line arguments
pub fn createFromArgs(allocator: std.mem.Allocator) !void {
    const config = cli_parser.parseArgs(allocator) catch |err| switch (err) {
        error.MissingArgument,
        error.InvalidGameMode,
        error.InvalidNumber,
        error.InvalidPlayerCount,
        error.InvalidLogLevel,
        error.InvalidDisplayMode,
        error.InvalidPlayerType,
        error.InvalidStackSize,
        error.InvalidBlindStructure,
        error.StackTooSmall,
        error.PlayerCountMismatch,
        error.InvalidTrainingIterations,
        error.InvalidThreadCount,
        error.UnknownArgument,
        error.InvalidPlayerConfig => {
            std.debug.print("Error parsing command line arguments: {}\n", .{err});
            cli_parser.CliParser.printHelp("poker_ai");
            return;
        },
        else => return err,
    };
    
    // Handle special flags
    if (config.help) {
        cli_parser.CliParser.printHelp("poker_ai");
        return;
    }
    
    if (config.version) {
        cli_parser.CliParser.printVersion();
        return;
    }
    
    // Run the appropriate mode
    switch (config.game_mode) {
        .play, .demo => try runTerminalUI(allocator, config),
        .train => {
            std.debug.print("Training mode not yet implemented.\n");
            std.debug.print("Use --mode play to start interactive game.\n");
        },
        .analyze => {
            std.debug.print("Analysis mode not yet implemented.\n");
            std.debug.print("Use --mode play to start interactive game.\n");
        },
    }
}

// Unit tests
test "terminal UI initialization" {
    const testing = std.testing;
    
    var config = try Config.default(testing.allocator);
    defer config.deinit(testing.allocator);
    
    var ui = try TerminalUI.init(testing.allocator, config);
    defer ui.deinit();
    
    try testing.expect(ui.is_running);
    try testing.expectEqual(TerminalUI.MenuState.main_menu, ui.current_menu);
}

test "game statistics" {
    const testing = std.testing;
    
    var stats = GameStats.init();
    try testing.expectEqual(@as(u32, 0), stats.hands_played);
    try testing.expectEqual(@as(f32, 0.0), stats.getWinRate());
    
    stats.hands_played = 10;
    stats.hands_won = 3;
    try testing.expectEqual(@as(f32, 0.3), stats.getWinRate());
}

test "menu item conversion" {
    const testing = std.testing;
    
    try testing.expectEqualStrings("Play Game", MainMenuItem.play_game.toString());
    try testing.expectEqualStrings("Settings", MainMenuItem.settings.toString());
    try testing.expectEqualStrings("Quit", MainMenuItem.quit.toString());
}