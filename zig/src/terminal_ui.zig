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
const action_validator = @import("action_validator.zig");
const hand_eval = @import("hand_eval.zig");

const Colors = ascii_cards.Colors;
const GameDisplay = game_display.GameDisplay;
const InputHandler = input_handler.InputHandler;
const Config = cli_parser.Config;
const PlayerConfig = cli_parser.PlayerConfig;
const Player = player.Player;
const TexasHoldemGameEngine = game_engine.TexasHoldemGameEngine;
const BettingStage = game_engine.BettingStage;
const ActionValidator = action_validator.ActionValidator;
const ActionType = action_validator.ActionType;
const HandEvaluator = hand_eval.HandEvaluator;

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
        const ascii_display_mode: ascii_cards.DisplayMode = switch (config.display_mode) {
            .compact => .compact,
            .normal => .normal,
            .detailed => .detailed,
        };
        const display = try GameDisplay.init(allocator, 120, 40, ascii_display_mode, !config.no_color);
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

            // Small delay to prevent busy waiting and reduce flashing
            std.Thread.sleep(50 * std.time.ns_per_ms); // ~20 FPS (more than enough for a poker game)
        }
    }

    /// Handle main menu navigation
    fn handleMainMenu(self: *TerminalUI) !void {
        const menu_items = [_]MainMenuItem{ .play_game, .train_ai, .analyze_hands, .settings, .view_stats, .quit };

        var selected_index: usize = 0;

        // Draw menu once initially
        try self.drawMainMenu(menu_items[0..], selected_index);

        while (self.current_menu == .main_menu and self.is_running) {
            const input_event = try self.input.handleMenu(&[_][]const u8{
                menu_items[0].toString(),
                menu_items[1].toString(),
                menu_items[2].toString(),
                menu_items[3].toString(),
                menu_items[4].toString(),
                menu_items[5].toString(),
            }, &selected_index, null);

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
                        .up, .down => {
                            // Redraw menu when selection changes
                            try self.drawMainMenu(menu_items[0..], selected_index);
                        },
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
            std.debug.print("╔═══════════════════════════════╗", .{});
        }

        self.moveCursor(title_y + 1, center_x - 15);
        if (self.display.use_color) {
            std.debug.print("{s}║      ZIG POKER AI v0.1.0      ║{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("║      ZIG POKER AI v0.1.0      ║", .{});
        }

        self.moveCursor(title_y + 2, center_x - 15);
        if (self.display.use_color) {
            std.debug.print("{s}╚═══════════════════════════════╝{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("╚═══════════════════════════════╝", .{});
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
            std.debug.print("Use W/S or ↑/↓ to navigate, Enter to select, Q to quit", .{});
        }
    }

    /// Handle settings menu
    fn handleSettingsMenu(self: *TerminalUI) !void {
        const menu_items = [_]SettingsMenuItem{ .display_mode, .sound_effects, .ai_difficulty, .betting_structure, .player_names, .save_settings, .back };

        var selected_index: usize = 0;

        // Draw menu once initially
        try self.drawSettingsMenu(menu_items[0..], selected_index);

        while (self.current_menu == .settings_menu and self.is_running) {
            const input_event = try self.input.handleMenu(&[_][]const u8{
                menu_items[0].toString(),
                menu_items[1].toString(),
                menu_items[2].toString(),
                menu_items[3].toString(),
                menu_items[4].toString(),
                menu_items[5].toString(),
                menu_items[6].toString(),
            }, &selected_index, null);

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
                        .up, .down => {
                            // Redraw menu when selection changes
                            try self.drawSettingsMenu(menu_items[0..], selected_index);
                        },
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
            std.debug.print("SETTINGS", .{});
        }

        // Current settings display
        const settings_y = title_y + 3;
        self.moveCursor(settings_y, 5);
        std.debug.print("Current Settings:", .{});

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
        // Clear screen once at the start of the game
        ascii_cards.Screen.clear();

        // Initialize game
        const game_config = game_engine.GameConfig{
            .small_blind = self.config.small_blind,
            .big_blind = self.config.big_blind,
            .initial_stack = self.config.starting_stack,
            .ante = 0,
        };

        var game = try TexasHoldemGameEngine.init(self.allocator, self.config.num_players, game_config);
        defer game.deinit();

        // Update player stacks from config (players are already initialized in game engine)
        for (self.config.players, 0..) |player_config, i| {
            if (i < game.num_players) {
                // Just update the stack size, don't replace the entire player
                game.players[i].stack = player_config.stack_size;
            }
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
            while (!game.isGameTerminal()) {
                // Render current game state
                try self.display.render(game.players[0..game.num_players], game.board[0..game.betting_stage.boardSize()], game.pot_manager.getTotalPot(), game.betting_manager.current_bet, game.betting_stage, game.dealer_button, if (game.current_player_index < game.num_players) game.current_player_index else null);

                // Handle current player's action
                if (game.current_player_index < game.num_players) {
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
            if (game.isGameTerminal() and self.current_menu == .in_game) {
                try self.showHandResult(&game);
                try self.input.waitForAnyKey("Press any key for next hand...");
            }
        }
    }

    /// Handle human player action
    fn handleHumanPlayerAction(self: *TerminalUI, current_player: *Player, game: *TexasHoldemGameEngine) !void {
        // Get available actions based on current game state
        const legal_actions = try game.getLegalActions();
        defer self.allocator.free(legal_actions);

        // Convert ActionTypes to action_validator.ActionType
        const validator_actions = try self.allocator.alloc(action_validator.ActionType, legal_actions.len);
        defer self.allocator.free(validator_actions);
        for (legal_actions, 0..) |action, i| {
            validator_actions[i] = @enumFromInt(@intFromEnum(action));
        }

        // Create a simple validation result for UI compatibility
        const validation = action_validator.ValidationResult{
            .is_valid = true,
            .error_code = .valid,
            .message = "",
            .suggested_actions = validator_actions,
            .min_raise_amount = game.betting_manager.getMinRaiseAmount(),
            .max_raise_amount = current_player.stack + current_player.current_bet,
            .call_amount = @max(0, @as(i32, @intCast(game.betting_manager.current_bet)) - @as(i32, @intCast(current_player.current_bet))),
        };

        if (validation.suggested_actions.len == 0) {
            // Player is all-in or folded, automatically continue
            return;
        }

        var selected_action_index: usize = 0;
        var raise_amount: u32 = validation.min_raise_amount;

        const InputMode = enum {
            selecting_action,
            entering_raise_amount,
        };

        var input_mode: InputMode = .selecting_action;

        while (true) {
            // Display available actions
            try self.displayActionMenu(validation.suggested_actions, selected_action_index, validation.call_amount, raise_amount, validation.min_raise_amount, validation.max_raise_amount, input_mode);

            // Handle input based on current mode
            switch (input_mode) {
                .selecting_action => {
                    const input_event = try self.input.getKeyInput();

                    switch (input_event) {
                        .menu_action => |action| {
                            switch (action) {
                                .up => {
                                    if (selected_action_index > 0) {
                                        selected_action_index -= 1;
                                    } else {
                                        selected_action_index = validation.suggested_actions.len - 1;
                                    }
                                },
                                .down => {
                                    selected_action_index = (selected_action_index + 1) % validation.suggested_actions.len;
                                },
                                .select => {
                                    const selected_action = validation.suggested_actions[selected_action_index];

                                    switch (selected_action) {
                                        .raise => {
                                            input_mode = .entering_raise_amount;
                                            raise_amount = validation.min_raise_amount;
                                        },
                                        else => {
                                            // Execute the action
                                            try self.executePlayerAction(current_player, game, selected_action, null);
                                            return;
                                        },
                                    }
                                },
                                .quit => return,
                                else => {},
                            }
                        },
                        else => {},
                    }
                },
                .entering_raise_amount => {
                    const input_event = try self.input.getRaiseAmountInput(raise_amount, validation.min_raise_amount, validation.max_raise_amount);

                    switch (input_event) {
                        .player_action => |action| {
                            if (action.amount) |amount| {
                                raise_amount = amount;
                            }
                        },
                        .menu_action => |action| {
                            switch (action) {
                                .select => {
                                    // Execute raise with current amount
                                    try self.executePlayerAction(current_player, game, .raise, raise_amount);
                                    return;
                                },
                                .back => {
                                    input_mode = .selecting_action;
                                },
                                .quit => return,
                                else => {},
                            }
                        },
                        else => {},
                    }
                },
            }
        }
    }

    /// Handle AI player action
    fn handleAIPlayerAction(self: *TerminalUI, current_player: *Player, game: *TexasHoldemGameEngine, ai_type: cli_parser.PlayerType) !void {
        // Get available actions
        const legal_actions = try game.getLegalActions();
        defer self.allocator.free(legal_actions);

        // Convert ActionTypes to action_validator.ActionType
        const validator_actions = try self.allocator.alloc(action_validator.ActionType, legal_actions.len);
        defer self.allocator.free(validator_actions);
        for (legal_actions, 0..) |action, i| {
            validator_actions[i] = @enumFromInt(@intFromEnum(action));
        }

        // Create a simple validation result for UI compatibility
        const validation = action_validator.ValidationResult{
            .is_valid = true,
            .error_code = .valid,
            .message = "",
            .suggested_actions = validator_actions,
            .min_raise_amount = game.betting_manager.getMinRaiseAmount(),
            .max_raise_amount = current_player.stack + current_player.current_bet,
            .call_amount = @max(0, @as(i32, @intCast(game.betting_manager.current_bet)) - @as(i32, @intCast(current_player.current_bet))),
        };

        if (validation.suggested_actions.len == 0) {
            return; // Player is all-in or folded
        }

        // Show AI thinking indicator
        try self.displayAIThinking(current_player, ai_type);

        // Simulate thinking time
        std.Thread.sleep(@as(u64, self.config.ai_think_time_ms) * std.time.ns_per_ms);

        // Choose action based on AI type
        var action: ActionType = undefined;
        var amount: ?u32 = null;

        switch (ai_type) {
            .ai_weak => {
                // Random strategy
                var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
                const random = prng.random();
                action = validation.suggested_actions[random.intRangeAtMost(usize, 0, validation.suggested_actions.len - 1)];

                if (action == .raise) {
                    amount = random.intRangeAtMost(u32, validation.min_raise_amount, validation.max_raise_amount);
                }
            },
            .ai_medium => {
                // Simple heuristic-based strategy
                action = self.getSimpleAIAction(current_player, game, validation);
                if (action == .raise) {
                    amount = validation.min_raise_amount;
                }
            },
            .ai_strong => {
                // TODO: Integrate with trained MCCFR strategy
                // For now, use simple strategy
                action = self.getSimpleAIAction(current_player, game, validation);
                if (action == .raise) {
                    amount = validation.min_raise_amount;
                }
            },
            else => {
                // Fallback to random for unknown types
                var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
                const random = prng.random();
                action = validation.suggested_actions[random.intRangeAtMost(usize, 0, validation.suggested_actions.len - 1)];

                if (action == .raise) {
                    amount = validation.min_raise_amount;
                }
            },
        }

        // Execute the action
        try self.executePlayerAction(current_player, game, action, amount);
    }

    /// Show hand result
    fn showHandResult(self: *TerminalUI, game: *TexasHoldemGameEngine) !void {
        ascii_cards.Screen.clear();

        const center_x = self.display.layout.center_x;
        var y: u16 = 3;

        // Title
        self.moveCursor(y, center_x - 10);
        if (self.display.use_color) {
            std.debug.print("{s}HAND RESULT{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("HAND RESULT", .{});
        }
        y += 2;

        // Show all players' cards and hand rankings
        const evaluator = HandEvaluator.init();

        // Determine winners and hand rankings
        var player_hands = try self.allocator.alloc(struct {
            player: *const Player,
            rank: u32,
            hand_name: []const u8,
        }, game.num_players);
        defer self.allocator.free(player_hands);

        var active_count: usize = 0;
        for (game.players[0..game.num_players]) |*player_ptr| {
            if (!player_ptr.is_active and !player_ptr.is_all_in) continue;

            // Convert u8 cards to u32 for hand evaluator compatibility
            var hole_cards_u32: [2]u32 = undefined;
            hole_cards_u32[0] = @intCast(player_ptr.hole_cards[0]);
            hole_cards_u32[1] = @intCast(player_ptr.hole_cards[1]);

            // Convert board cards
            var board_cards: [5]u32 = undefined;
            const board_size = game.betting_stage.boardSize();
            for (0..board_size) |i| {
                board_cards[i] = @intCast(game.board[i]);
            }

            const rank = evaluator.evaluate(hole_cards_u32, board_cards[0..board_size]);
            const hand_type = hand_eval.HandEvaluator.getHandType(rank);
            const hand_name = hand_eval.HandEvaluator.handTypeToString(hand_type);

            player_hands[active_count] = .{
                .player = player_ptr,
                .rank = rank,
                .hand_name = hand_name,
            };
            active_count += 1;
        }

        // Sort by rank (lower is better in most evaluators)
        std.sort.insertion(@TypeOf(player_hands[0]), player_hands[0..active_count], {}, struct {
            fn lessThan(_: void, lhs: @TypeOf(player_hands[0]), rhs: @TypeOf(player_hands[0])) bool {
                return lhs.rank < rhs.rank;
            }
        }.lessThan);

        // Display results
        for (player_hands[0..active_count], 0..) |hand, i| {
            self.moveCursor(y, center_x - 25);

            const position_text = if (i == 0) "WINNER" else switch (i) {
                1 => "2nd",
                2 => "3rd",
                else => "4th+",
            };

            if (self.display.use_color and i == 0) {
                std.debug.print("{s}{s}: Player {d} with {s}{s}", .{ Colors.WHITE, position_text, hand.player.id, hand.hand_name, Colors.RESET });
            } else {
                std.debug.print("{s}: Player {d} with {s}", .{ position_text, hand.player.id, hand.hand_name });
            }

            // Show cards
            y += 1;
            self.moveCursor(y, center_x - 25);
            // TODO: Implement card display with ascii_cards.renderMultipleCards
            std.debug.print("Cards: {d} {d}", .{ hand.player.hole_cards[0], hand.player.hole_cards[1] });
            y += 2;
        }

        // Update statistics for human player (assumed to be player 0)
        if (game.players[0].id == 0) { // Human player
            if (player_hands.len > 0 and player_hands[0].player.id == 0) {
                self.stats.hands_won += 1;
                const pot_won = game.pot_manager.getTotalPot();
                self.stats.total_winnings += @intCast(pot_won);
                if (pot_won > self.stats.biggest_pot_won) {
                    self.stats.biggest_pot_won = pot_won;
                }
            }
        }

        // Show pot distribution
        y += 2;
        self.moveCursor(y, center_x - 15);
        std.debug.print("Pot Size: ${d}", .{game.pot_manager.getTotalPot()});
    }

    /// Handle training mode
    fn handleTraining(self: *TerminalUI) !void {
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Training mode not yet implemented.", .{});
        self.moveCursor(12, 40);
        std.debug.print("Press any key to return to main menu...", .{});

        try self.input.waitForAnyKey(null);
        self.current_menu = .main_menu;
    }

    /// Handle analysis mode
    fn handleAnalysis(self: *TerminalUI) !void {
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Analysis mode not yet implemented.", .{});
        self.moveCursor(12, 40);
        std.debug.print("Press any key to return to main menu...", .{});

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
            std.debug.print("SESSION STATISTICS", .{});
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
        std.debug.print("Press Enter to return to main menu...", .{});

        // Flush output to ensure everything is displayed
        _ = std.fs.File.stdout().write("") catch {};

        // Use readWithTimeout to properly wait for input
        // This avoids the infinite loop when raw mode check fails
        while (true) {
            const char = try self.input.readWithTimeout(100) orelse {
                // Check if we should exit on timeout (allows Ctrl+C to work)
                if (!self.is_running) break;
                continue;
            };
            if (char == '\n' or char == '\r' or char == 'q' or char == 'Q' or char == 27) { // 27 = ESC
                break;
            }
        }

        // Redraw the main menu when returning
        // No need - the main menu loop will handle this
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
        // Convert ascii_cards.DisplayMode to cli_parser.Config.DisplayMode
        const ascii_mode = modes[selected];
        self.config.display_mode = switch (ascii_mode) {
            .compact => .compact,
            .normal => .normal,
            .detailed => .detailed,
        };
        self.display.display_mode = modes[selected];

        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Display mode changed to: {s}", .{mode_names[selected]});
        self.moveCursor(12, 40);
        std.debug.print("Press any key to continue...", .{});

        try self.input.waitForAnyKey(null);
    }

    fn changeAIDifficulty(self: *TerminalUI) !void {
        // TODO: Implement AI difficulty change
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("AI difficulty change not yet implemented.", .{});
        try self.input.waitForAnyKey("Press any key to continue...");
    }

    fn changeBettingStructure(self: *TerminalUI) !void {
        // TODO: Implement betting structure change
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Betting structure change not yet implemented.", .{});
        try self.input.waitForAnyKey("Press any key to continue...");
    }

    fn changePlayerNames(self: *TerminalUI) !void {
        // TODO: Implement player name change
        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Player name change not yet implemented.", .{});
        try self.input.waitForAnyKey("Press any key to continue...");
    }

    fn saveSettings(self: *TerminalUI) !void {
        // Create settings directory if it doesn't exist
        std.fs.cwd().makeDir(".poker_ai") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Create settings JSON
        var settings = std.json.ObjectMap.init(self.allocator);
        defer settings.deinit();

        try settings.put("display_mode", std.json.Value{ .string = @tagName(self.config.display_mode) });
        try settings.put("use_color", std.json.Value{ .bool = !self.config.no_color });
        try settings.put("ai_think_time_ms", std.json.Value{ .integer = @intCast(self.config.ai_think_time_ms) });
        try settings.put("num_players", std.json.Value{ .integer = @intCast(self.config.num_players) });
        try settings.put("starting_stack", std.json.Value{ .integer = @intCast(self.config.starting_stack) });
        try settings.put("small_blind", std.json.Value{ .integer = @intCast(self.config.small_blind) });
        try settings.put("big_blind", std.json.Value{ .integer = @intCast(self.config.big_blind) });

        // Save player configurations
        var players_array = std.json.Array.init(self.allocator);
        defer players_array.deinit();

        for (self.config.players[0..self.config.num_players]) |player_config| {
            var player_obj = std.json.ObjectMap.init(self.allocator);
            defer player_obj.deinit();

            try player_obj.put("type", std.json.Value{ .string = @tagName(player_config.type) });
            try player_obj.put("name", std.json.Value{ .string = player_config.name });
            try player_obj.put("stack_size", std.json.Value{ .integer = @intCast(player_config.stack_size) });

            try players_array.append(std.json.Value{ .object = player_obj });
        }

        try settings.put("players", std.json.Value{ .array = players_array });

        // Write to file - simplified for Zig 0.15.1
        // TODO: Fix full JSON serialization later
        const file = try std.fs.cwd().createFile(".poker_ai/settings.json", .{});
        defer file.close();
        
        // Write a simple JSON representation
        try file.writeAll("{\n");
        try file.writeAll("  \"game_type\": \"");
        try file.writeAll(@tagName(self.config.game_mode));
        try file.writeAll("\",\n");
        try file.writeAll("  \"small_blind\": ");
        var buf: [32]u8 = undefined;
        const blind_str = try std.fmt.bufPrint(&buf, "{d}", .{self.config.small_blind});
        try file.writeAll(blind_str);
        try file.writeAll(",\n");
        try file.writeAll("  \"players\": [");
        for (self.config.players, 0..) |p, i| {
            if (i > 0) try file.writeAll(", ");
            try file.writeAll("{\"name\": \"");
            try file.writeAll(p.name);
            try file.writeAll("\", \"type\": \"");
            try file.writeAll(@tagName(p.type));
            try file.writeAll("\"}");
        }
        try file.writeAll("]\n");
        try file.writeAll("}\n");

        ascii_cards.Screen.clear();
        self.moveCursor(10, 40);
        std.debug.print("Settings saved successfully to .poker_ai/settings.json", .{});
        try self.input.waitForAnyKey("Press any key to continue...");
    }

    /// Load settings from file
    pub fn loadSettings(allocator: std.mem.Allocator, config: *cli_parser.Config) !void {
        const file = std.fs.cwd().openFile(".poker_ai/settings.json", .{}) catch |err| switch (err) {
            error.FileNotFound => return, // No settings file, use defaults
            else => return err,
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const json_content = try allocator.alloc(u8, file_size);
        defer allocator.free(json_content);

        _ = try file.readAll(json_content);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Load display mode
        if (root.get("display_mode")) |mode_value| {
            const mode_str = mode_value.string;
            if (std.mem.eql(u8, mode_str, "compact")) {
                config.display_mode = .compact;
            } else if (std.mem.eql(u8, mode_str, "normal")) {
                config.display_mode = .normal;
            } else if (std.mem.eql(u8, mode_str, "detailed")) {
                config.display_mode = .detailed;
            }
        }

        // Load other settings
        if (root.get("use_color")) |color_value| {
            config.no_color = !color_value.bool;
        }

        if (root.get("ai_think_time_ms")) |think_time_value| {
            config.ai_think_time_ms = @intCast(think_time_value.integer);
        }

        if (root.get("num_players")) |players_value| {
            config.num_players = @intCast(players_value.integer);
        }

        if (root.get("starting_stack")) |stack_value| {
            config.starting_stack = @intCast(stack_value.integer);
        }

        if (root.get("small_blind")) |sb_value| {
            config.small_blind = @intCast(sb_value.integer);
        }

        if (root.get("big_blind")) |bb_value| {
            config.big_blind = @intCast(bb_value.integer);
        }

        // Load players
        if (root.get("players")) |players_value| {
            for (players_value.array.items, 0..) |player_value, i| {
                if (i >= config.players.len) break;

                const player_obj = player_value.object;

                if (player_obj.get("type")) |type_value| {
                    const type_str = type_value.string;
                    if (std.mem.eql(u8, type_str, "human")) {
                        config.players[i].type = .human;
                    } else if (std.mem.eql(u8, type_str, "ai_weak")) {
                        config.players[i].type = .ai_weak;
                    } else if (std.mem.eql(u8, type_str, "ai_medium")) {
                        config.players[i].type = .ai_medium;
                    } else if (std.mem.eql(u8, type_str, "ai_strong")) {
                        config.players[i].type = .ai_strong;
                    } else if (std.mem.eql(u8, type_str, "ai_expert")) {
                        config.players[i].type = .ai_expert;
                    }
                }

                if (player_obj.get("name")) |name_value| {
                    // Free existing name and allocate new one
                    allocator.free(config.players[i].name);
                    config.players[i].name = try allocator.dupe(u8, name_value.string);
                }

                if (player_obj.get("stack_size")) |stack_value| {
                    config.players[i].stack_size = @intCast(stack_value.integer);
                }
            }
        }
    }

    /// Helper to move cursor
    fn moveCursor(self: *TerminalUI, row: u16, col: u16) void {
        _ = self; // Remove unused variable warning
        ascii_cards.Screen.moveTo(row, col);
    }

    /// Display action menu for human player
    fn displayActionMenu(
        self: *TerminalUI,
        actions: []const ActionType,
        selected_index: usize,
        call_amount: u32,
        raise_amount: u32,
        min_raise: u32,
        max_raise: u32,
        input_mode: anytype, // InputMode enum from handleHumanPlayerAction
    ) !void {
        const InputMode = @TypeOf(input_mode);

        // Clear bottom portion for action menu
        for (0..10) |i| {
            self.moveCursor(@intCast(self.display.layout.height - 10 + i), 0);
            std.debug.print("{s}", .{" " ** 120}); // Clear line
        }

        var y = self.display.layout.height - 8;
        const center_x = self.display.layout.center_x;

        // Title
        self.moveCursor(y, center_x - 10);
        if (self.display.use_color) {
            std.debug.print("{s}CHOOSE ACTION{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("CHOOSE ACTION", .{});
        }
        y += 2;

        switch (input_mode) {
            InputMode.selecting_action => {
                // Display available actions
                for (actions, 0..) |action, i| {
                    self.moveCursor(y, center_x - 20);

                    var action_text = try std.ArrayList(u8).initCapacity(self.allocator, 0);
                    defer action_text.deinit(self.allocator);

                    switch (action) {
                        .call => try action_text.writer(self.allocator).print("Call (${d})", .{call_amount}),
                        .raise => try action_text.writer(self.allocator).print("Raise (min ${d})", .{min_raise}),
                        .fold => try action_text.writer(self.allocator).print("Fold", .{}),
                        .check => try action_text.writer(self.allocator).print("Check", .{}),
                        .all_in => try action_text.writer(self.allocator).print("All-in", .{}),
                    }

                    if (i == selected_index) {
                        if (self.display.use_color) {
                            std.debug.print("{s}>>> {s} <<<{s}", .{ Colors.BOLD, action_text.items, Colors.RESET });
                        } else {
                            std.debug.print(">>> {s} <<<", .{action_text.items});
                        }
                    } else {
                        std.debug.print("    {s}", .{action_text.items});
                    }
                    y += 1;
                }

                // Instructions
                y += 1;
                self.moveCursor(y, center_x - 25);
                if (self.display.use_color) {
                    std.debug.print("{s}Use W/S or ↑/↓ to navigate, Enter to select, Q to quit{s}", .{ Colors.DIM, Colors.RESET });
                } else {
                    std.debug.print("Use W/S or ↑/↓ to navigate, Enter to select, Q to quit", .{});
                }
            },
            InputMode.entering_raise_amount => {
                // Raise amount input
                self.moveCursor(y, center_x - 15);
                std.debug.print("Enter raise amount: ${d}", .{raise_amount});
                y += 1;

                self.moveCursor(y, center_x - 15);
                std.debug.print("Min: ${d}  Max: ${d}", .{ min_raise, max_raise });
                y += 2;

                self.moveCursor(y, center_x - 25);
                if (self.display.use_color) {
                    std.debug.print("{s}Use +/- to adjust, Enter to confirm, Backspace to cancel{s}", .{ Colors.DIM, Colors.RESET });
                } else {
                    std.debug.print("Use +/- to adjust, Enter to confirm, Backspace to cancel", .{});
                }
            },
        }
    }

    /// Display AI thinking indicator
    fn displayAIThinking(self: *TerminalUI, current_player: *const Player, ai_type: cli_parser.PlayerType) !void {
        const y = self.display.layout.height - 3;
        const center_x = self.display.layout.center_x;

        // Clear the line first
        self.moveCursor(y, 0);
        std.debug.print("{s}", .{" " ** 120});

        self.moveCursor(y, center_x - 20);

        const ai_name = switch (ai_type) {
            .ai_weak => "Weak AI",
            .ai_medium => "Medium AI",
            .ai_strong => "Strong AI",
            else => "AI",
        };

        if (self.display.use_color) {
            std.debug.print("{s}Player {d} ({s}) is thinking...{s}", .{ Colors.WHITE, current_player.id, ai_name, Colors.RESET });
        } else {
            std.debug.print("Player {d} ({s}) is thinking...", .{ current_player.id, ai_name });
        }
    }

    /// Execute a player action
    fn executePlayerAction(self: *TerminalUI, current_player: *Player, game: *TexasHoldemGameEngine, action: ActionType, amount: ?u32) !void {
        // Convert action to game engine format and execute
        const game_action = switch (action) {
            .fold => game_engine.Action.fold(current_player.id),
            .check => game_engine.Action.check(current_player.id),
            .call => game_engine.Action.call(current_player.id),
            .raise => blk: {
                const raise_amount = amount orelse return error.MissingRaiseAmount;
                break :blk game_engine.Action.raise(current_player.id, raise_amount);
            },
            .all_in => blk: {
                const all_in_amount = current_player.stack;
                break :blk game_engine.Action.allIn(current_player.id, all_in_amount);
            },
        };

        try game.applyAction(game_action);

        // Add to action history
        const action_entry = game_display.ActionHistoryEntry{
            .player_name = try std.fmt.allocPrint(self.allocator, "Player {d}", .{current_player.id}),
            .action = switch (action) {
                .fold => "fold",
                .call => "call",
                .raise => "raise",
                .check => "check",
                .all_in => "all_in",
            },
            .amount = amount,
            .stage = game.betting_stage,
        };
        try self.display.action_history.append(self.allocator, action_entry);
    }

    /// Simple AI decision making
    fn getSimpleAIAction(
        self: *TerminalUI,
        current_player: *const Player,
        game: *const TexasHoldemGameEngine,
        validation: anytype, // ValidationResult
    ) ActionType {
        _ = game;

        // Simple heuristic: fold if low chips, call if medium, raise if high
        const stack_ratio = @as(f32, @floatFromInt(current_player.stack)) / @as(f32, @floatFromInt(self.config.starting_stack));

        // Check if we can check for free
        for (validation.suggested_actions) |action| {
            if (action == .check) return .check;
        }

        if (stack_ratio < 0.2) {
            // Low on chips, be conservative
            for (validation.suggested_actions) |action| {
                if (action == .fold) return .fold;
                if (action == .call and validation.call_amount < current_player.stack / 4) return .call;
            }
            return .fold;
        } else if (stack_ratio > 0.7) {
            // High chips, be aggressive
            for (validation.suggested_actions) |action| {
                if (action == .raise) return .raise;
                if (action == .call) return .call;
            }
        }

        // Medium stack, balanced play
        for (validation.suggested_actions) |action| {
            if (action == .call) return .call;
        }

        return .fold;
    }
};

/// Main entry point for terminal UI
pub fn runTerminalUI(allocator: std.mem.Allocator, mut_config: Config) !void {
    var config = mut_config;

    // Try to load saved settings
    TerminalUI.loadSettings(allocator, &config) catch |err| {
        // If loading fails, continue with provided config
        std.debug.print("Warning: Could not load settings: {}\n", .{err});
    };

    var ui = try TerminalUI.init(allocator, config);
    defer ui.deinit();

    try ui.run();
}

/// Create terminal UI from command line arguments
pub fn createFromArgs(allocator: std.mem.Allocator) !void {
    const config = cli_parser.parseArgs(allocator) catch |err| switch (err) {
        error.MissingArgument, error.InvalidGameMode, error.InvalidNumber, error.InvalidPlayerCount, error.InvalidLogLevel, error.InvalidDisplayMode, error.InvalidPlayerType, error.InvalidStackSize, error.InvalidBlindStructure, error.StackTooSmall, error.PlayerCountMismatch, error.InvalidTrainingIterations, error.InvalidThreadCount, error.UnknownArgument, error.InvalidPlayerConfig => {
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
            std.debug.print("Training mode not yet implemented.\n", .{});
            std.debug.print("Use --mode play to start interactive game.\n", .{});
        },
        .analyze => {
            std.debug.print("Analysis mode not yet implemented.\n", .{});
            std.debug.print("Use --mode play to start interactive game.\n", .{});
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
