//! Game Display
//!
//! Visual representation of poker game state using ASCII art
//! Features:
//! - ASCII poker table layout with player positions
//! - Community cards and pot visualization
//! - Player chip stacks and statuses
//! - Action history and betting information
//! - Responsive layout for different terminal sizes

const std = @import("std");
const ascii_cards = @import("ascii_cards.zig");
const game_engine = @import("game_engine.zig");
const player = @import("player.zig");

const Card = ascii_cards.Card;
const Player = player.Player;
const BettingStage = game_engine.BettingStage;
const Colors = ascii_cards.Colors;
const DisplayMode = ascii_cards.DisplayMode;

/// Table layout configuration
pub const TableLayout = struct {
    width: u16,
    height: u16,
    center_x: u16,
    center_y: u16,

    pub fn init(width: u16, height: u16) TableLayout {
        return TableLayout{
            .width = width,
            .height = height,
            .center_x = width / 2,
            .center_y = height / 2,
        };
    }

    /// Get player position on table (returns x, y coordinates)
    pub fn getPlayerPosition(self: TableLayout, player_index: u8, total_players: u8) struct { x: u16, y: u16 } {
        const angle = @as(f32, @floatFromInt(player_index)) * (2.0 * std.math.pi) / @as(f32, @floatFromInt(total_players));
        const radius_x = @as(f32, @floatFromInt(self.width)) * 0.35;
        const radius_y = @as(f32, @floatFromInt(self.height)) * 0.3;

        const x = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.center_x)) + radius_x * @cos(angle - std.math.pi / 2.0)));
        const y = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.center_y)) + radius_y * @sin(angle - std.math.pi / 2.0)));

        return .{ .x = x, .y = y };
    }
};

/// Action history entry
pub const ActionHistoryEntry = struct {
    player_name: []const u8,
    action: []const u8,
    amount: ?u32,
    stage: BettingStage,

    pub fn format(self: ActionHistoryEntry, allocator: std.mem.Allocator) ![]u8 {
        if (self.amount) |amt| {
            return try std.fmt.allocPrint(allocator, "{s} {s} {d}", .{ self.player_name, self.action, amt });
        } else {
            return try std.fmt.allocPrint(allocator, "{s} {s}", .{ self.player_name, self.action });
        }
    }
};

/// Game display state
pub const GameDisplay = struct {
    allocator: std.mem.Allocator,
    layout: TableLayout,
    display_mode: DisplayMode,
    use_color: bool,
    action_history: std.ArrayList(ActionHistoryEntry),

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16, display_mode: DisplayMode, use_color: bool) GameDisplay {
        return GameDisplay{
            .allocator = allocator,
            .layout = TableLayout.init(width, height),
            .display_mode = display_mode,
            .use_color = use_color,
            .action_history = std.ArrayList(ActionHistoryEntry).init(allocator),
        };
    }

    pub fn deinit(self: *GameDisplay) void {
        self.action_history.deinit();
    }

    /// Clear screen and draw complete game state
    pub fn render(self: *GameDisplay, players: []const Player, community_cards: []const Card, pot_size: u32, current_bet: u32, betting_stage: BettingStage, dealer_position: u8, current_player: ?u8) !void {
        // Clear screen and move cursor to home position
        // This ensures a clean display without artifacts
        std.debug.print("\x1b[2J", .{}); // Clear entire screen
        ascii_cards.Screen.moveTo(1, 1);

        // Draw border
        try self.drawBorder();

        // Draw table
        try self.drawTable();

        // Draw community cards
        try self.drawCommunityCards(community_cards, betting_stage);

        // Draw pot
        try self.drawPot(pot_size, current_bet);

        // Draw players
        try self.drawPlayers(players, dealer_position, current_player);

        // Draw betting stage
        try self.drawBettingStage(betting_stage);

        // Draw action history
        try self.drawActionHistory();

        // Draw status bar
        try self.drawStatusBar(players);

        // Flush output to ensure smooth rendering
        std.io.getStdOut().writer().writeAll("") catch {};
    }

    /// Draw table border
    fn drawBorder(self: *GameDisplay) !void {
        const width = self.layout.width;
        const height = self.layout.height;

        // Top and bottom borders
        for (0..width) |x| {
            self.moveCursor(0, @intCast(x));
            std.debug.print("{s}", .{"═"});
            self.moveCursor(height - 1, @intCast(x));
            std.debug.print("{s}", .{"═"});
        }

        // Left and right borders
        for (0..height) |y| {
            self.moveCursor(@intCast(y), 0);
            std.debug.print("{s}", .{"║"});
            self.moveCursor(@intCast(y), width - 1);
            std.debug.print("{s}", .{"║"});
        }

        // Corners
        self.moveCursor(0, 0);
        std.debug.print("{s}", .{"╔"});
        self.moveCursor(0, width - 1);
        std.debug.print("{s}", .{"╗"});
        self.moveCursor(height - 1, 0);
        std.debug.print("{s}", .{"╚"});
        self.moveCursor(height - 1, width - 1);
        std.debug.print("{s}", .{"╝"});
    }

    /// Draw poker table ellipse
    fn drawTable(self: *GameDisplay) !void {
        const center_x = self.layout.center_x;
        const center_y = self.layout.center_y;
        const table_width = self.layout.width / 3;
        const table_height = self.layout.height / 4;

        // Draw elliptical table outline
        for (0..self.layout.height) |y| {
            for (0..self.layout.width) |x| {
                const dx = @as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(center_x));
                const dy = @as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(center_y));

                const ellipse_eq = (dx * dx) / (@as(f32, @floatFromInt(table_width)) * @as(f32, @floatFromInt(table_width))) +
                    (dy * dy) / (@as(f32, @floatFromInt(table_height)) * @as(f32, @floatFromInt(table_height)));

                if (ellipse_eq >= 0.95 and ellipse_eq <= 1.05) {
                    self.moveCursor(@intCast(y), @intCast(x));
                    if (self.use_color) {
                        std.debug.print("{s}●{s}", .{ Colors.DIM, Colors.RESET });
                    } else {
                        std.debug.print("{s}", .{"●"});
                    }
                }
            }
        }
    }

    /// Draw community cards
    fn drawCommunityCards(self: *GameDisplay, cards: []const Card, stage: BettingStage) !void {
        const num_cards: u8 = switch (stage) {
            .pre_flop => 0,
            .flop => 3,
            .turn => 4,
            .river, .show_down, .terminal => 5,
        };

        if (num_cards == 0) return;

        const cards_to_show = cards[0..@min(num_cards, cards.len)];

        // Position community cards in center of table
        const start_x = self.layout.center_x - (@as(u16, @intCast(cards_to_show.len)) * 4);
        const y = self.layout.center_y - 2;

        switch (self.display_mode) {
            .compact => {
                self.moveCursor(y, start_x);
                if (self.use_color) std.debug.print("{s}Community:{s} ", .{ Colors.BOLD, Colors.RESET });

                for (cards_to_show, 0..) |card, i| {
                    if (i > 0) std.debug.print("{c}", .{' '});
                    const card_str = try ascii_cards.renderCompact(card, self.allocator);
                    defer self.allocator.free(card_str);
                    std.debug.print("{s}", .{card_str});
                }
            },
            .normal => {
                // Render cards side by side
                const cards_str = try ascii_cards.renderMultipleCards(cards_to_show, .normal, self.allocator);
                defer self.allocator.free(cards_str);

                var lines = std.mem.splitScalar(u8, cards_str, '\n');
                var line_index: u16 = 0;

                while (lines.next()) |line| {
                    self.moveCursor(y + line_index, start_x);
                    std.debug.print("{s}", .{line});
                    line_index += 1;
                }
            },
            .detailed => {
                // Similar to normal but with detailed cards
                const cards_str = try ascii_cards.renderMultipleCards(cards_to_show, .detailed, self.allocator);
                defer self.allocator.free(cards_str);

                var lines = std.mem.splitScalar(u8, cards_str, '\n');
                var line_index: u16 = 0;

                while (lines.next()) |line| {
                    self.moveCursor(y + line_index, start_x);
                    std.debug.print("{s}", .{line});
                    line_index += 1;
                }
            },
        }
    }

    /// Draw pot information
    fn drawPot(self: *GameDisplay, pot_size: u32, current_bet: u32) !void {
        const x = self.layout.center_x - 10;
        const y = self.layout.center_y + 4;

        self.moveCursor(y, x);
        if (self.use_color) {
            std.debug.print("{s}POT:{s} {s}{d}{s}", .{ Colors.BOLD, Colors.RESET, Colors.RED, pot_size, Colors.RESET });
        } else {
            std.debug.print("POT: {d}", .{pot_size});
        }

        if (current_bet > 0) {
            self.moveCursor(y + 1, x);
            if (self.use_color) {
                std.debug.print("{s}BET:{s} {d}", .{ Colors.BOLD, Colors.RESET, current_bet });
            } else {
                std.debug.print("BET: {d}", .{current_bet});
            }
        }
    }

    /// Draw all players around the table
    fn drawPlayers(self: *GameDisplay, players: []const Player, dealer_position: u8, current_player: ?u8) !void {
        for (players, 0..) |p, i| {
            const player_index = @as(u8, @intCast(i));
            try self.drawPlayer(p, player_index, players.len, dealer_position, current_player);
        }
    }

    /// Draw individual player
    fn drawPlayer(self: *GameDisplay, p: Player, player_index: u8, total_players: usize, dealer_position: u8, current_player: ?u8) !void {
        const pos = self.layout.getPlayerPosition(player_index, @intCast(total_players));
        const is_dealer = player_index == dealer_position;
        const is_current = if (current_player) |cp| cp == player_index else false;

        // Player name and status
        var name_line = std.ArrayList(u8).init(self.allocator);
        defer name_line.deinit();

        if (is_dealer) try name_line.appendSlice("(D) ");
        if (p.is_small_blind) try name_line.appendSlice("(SB) ");
        if (p.is_big_blind) try name_line.appendSlice("(BB) ");

        try name_line.writer().print("P{d}", .{player_index + 1});

        if (is_current and self.use_color) {
            self.moveCursor(pos.y - 2, pos.x - 5);
            std.debug.print("{s}>>> {s} <<<{s}", .{ Colors.BOLD, name_line.items, Colors.RESET });
        } else {
            self.moveCursor(pos.y - 2, pos.x - 5);
            std.debug.print("{s}", .{name_line.items});
        }

        // Player stack
        self.moveCursor(pos.y - 1, pos.x - 5);
        if (self.use_color) {
            const color = if (p.stack < 100) Colors.RED else if (p.stack < 500) Colors.DIM else Colors.RESET;
            std.debug.print("{s}${d}{s}", .{ color, p.stack, Colors.RESET });
        } else {
            std.debug.print("${d}", .{p.stack});
        }

        // Current bet
        if (p.current_bet > 0) {
            self.moveCursor(pos.y, pos.x - 5);
            if (self.use_color) {
                std.debug.print("{s}Bet: {d}{s}", .{ Colors.RED, p.current_bet, Colors.RESET });
            } else {
                std.debug.print("Bet: {d}", .{p.current_bet});
            }
        }

        // Player status
        self.moveCursor(pos.y + 1, pos.x - 5);
        const status = if (!p.is_active) "FOLDED" else if (p.is_all_in) "ALL-IN" else if (p.is_sitting_out) "SITTING OUT" else "ACTIVE";

        if (self.use_color) {
            const color = if (!p.is_active) Colors.DIM else if (p.is_all_in) Colors.RED else Colors.RESET;
            std.debug.print("{s}{s}{s}", .{ color, status, Colors.RESET });
        } else {
            std.debug.print("{s}", .{status});
        }

        // Hole cards (if visible - for human player or showdown)
        if (p.has_cards and p.hasValidCards()) {
            const cards = p.getHoleCards() catch return;

            switch (self.display_mode) {
                .compact => {
                    self.moveCursor(pos.y + 2, pos.x - 5);
                    const card1_str = try ascii_cards.renderCompact(cards[0], self.allocator);
                    defer self.allocator.free(card1_str);
                    const card2_str = try ascii_cards.renderCompact(cards[1], self.allocator);
                    defer self.allocator.free(card2_str);
                    std.debug.print("{s} {s}", .{ card1_str, card2_str });
                },
                .normal, .detailed => {
                    // For now, show compact even in normal/detailed mode for space
                    self.moveCursor(pos.y + 2, pos.x - 5);
                    const card1_str = try ascii_cards.renderCompact(cards[0], self.allocator);
                    defer self.allocator.free(card1_str);
                    const card2_str = try ascii_cards.renderCompact(cards[1], self.allocator);
                    defer self.allocator.free(card2_str);
                    std.debug.print("{s} {s}", .{ card1_str, card2_str });
                },
            }
        } else if (p.has_cards) {
            // Face down cards
            self.moveCursor(pos.y + 2, pos.x - 5);
            if (self.use_color) {
                std.debug.print("{s}[?] [?]{s}", .{ Colors.DIM, Colors.RESET });
            } else {
                std.debug.print("{s}", .{"[?] [?]"});
            }
        }
    }

    /// Draw current betting stage
    fn drawBettingStage(self: *GameDisplay, stage: BettingStage) !void {
        const stage_str = switch (stage) {
            .pre_flop => "Pre-Flop",
            .flop => "Flop",
            .turn => "Turn",
            .river => "River",
            .show_down => "Showdown",
            .terminal => "Hand Complete",
        };

        const x = 2;
        const y = 2;

        self.moveCursor(y, x);
        if (self.use_color) {
            std.debug.print("{s}STAGE:{s} {s}", .{ Colors.BOLD, Colors.RESET, stage_str });
        } else {
            std.debug.print("STAGE: {s}", .{stage_str});
        }
    }

    /// Draw action history
    fn drawActionHistory(self: *GameDisplay) !void {
        const x = 2;
        var y = self.layout.height - 8;

        self.moveCursor(y, x);
        if (self.use_color) {
            std.debug.print("{s}RECENT ACTIONS:{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("{s}", .{"RECENT ACTIONS:"});
        }
        y += 1;

        // Show last 5 actions
        const start_index = if (self.action_history.items.len > 5)
            self.action_history.items.len - 5
        else
            0;

        for (self.action_history.items[start_index..]) |entry| {
            self.moveCursor(y, x);
            const action_str = try entry.format(self.allocator);
            defer self.allocator.free(action_str);

            if (self.use_color) {
                std.debug.print("{s}{s}{s}", .{ Colors.DIM, action_str, Colors.RESET });
            } else {
                std.debug.print("{s}", .{action_str});
            }
            y += 1;
        }
    }

    /// Draw status bar at bottom
    fn drawStatusBar(self: *GameDisplay, players: []const Player) !void {
        const y = self.layout.height - 2;
        const x = 2;

        var active_count: u8 = 0;
        var total_chips: u32 = 0;

        for (players) |p| {
            if (p.is_active) active_count += 1;
            total_chips += p.stack + p.total_bet;
        }

        self.moveCursor(y, x);
        if (self.use_color) {
            std.debug.print("{s}Active Players: {d} | Total Chips: {d} | [Q]uit{s}", .{ Colors.DIM, active_count, total_chips, Colors.RESET });
        } else {
            std.debug.print("Active Players: {d} | Total Chips: {d} | [Q]uit", .{ active_count, total_chips });
        }
    }

    /// Add action to history
    pub fn addAction(self: *GameDisplay, player_name: []const u8, action: []const u8, amount: ?u32, stage: BettingStage) !void {
        try self.action_history.append(ActionHistoryEntry{
            .player_name = player_name,
            .action = action,
            .amount = amount,
            .stage = stage,
        });

        // Keep only last 20 actions to prevent memory growth
        if (self.action_history.items.len > 20) {
            _ = self.action_history.orderedRemove(0);
        }
    }

    /// Clear action history
    pub fn clearActionHistory(self: *GameDisplay) void {
        self.action_history.clearRetainingCapacity();
    }

    /// Helper to move cursor
    fn moveCursor(self: *GameDisplay, row: u16, col: u16) void {
        _ = self; // Remove unused variable warning
        ascii_cards.Screen.moveTo(row, col);
    }

    /// Show hand result screen
    pub fn showHandResult(self: *GameDisplay, players: []const Player, winner_indices: []const u8, winning_hand_description: []const u8, pot_distribution: []const u32) !void {
        ascii_cards.Screen.clear();

        const center_x = self.layout.center_x;
        var y: u16 = 5;

        // Title
        self.moveCursor(y, center_x - 10);
        if (self.use_color) {
            std.debug.print("{s}HAND RESULT{s}", .{ Colors.BOLD, Colors.RESET });
        } else {
            std.debug.print("{s}", .{"HAND RESULT"});
        }
        y += 3;

        // Winner(s)
        self.moveCursor(y, center_x - 15);
        if (winner_indices.len == 1) {
            std.debug.print("Winner: Player {d}", .{winner_indices[0] + 1});
        } else {
            std.debug.print("{s}", .{"Split pot between players: "});
            for (winner_indices, 0..) |idx, i| {
                if (i > 0) std.debug.print("{s}", .{", "});
                std.debug.print("{d}", .{idx + 1});
            }
        }
        y += 2;

        // Winning hand
        self.moveCursor(y, center_x - 15);
        std.debug.print("Winning hand: {s}", .{winning_hand_description});
        y += 3;

        // Show all players' hands and winnings
        for (players, 0..) |p, i| {
            self.moveCursor(y, 5);

            const player_index = @as(u8, @intCast(i));
            const winnings = if (player_index < pot_distribution.len) pot_distribution[player_index] else 0;

            if (p.hasValidCards()) {
                const cards = p.getHoleCards() catch continue;
                const card1_str = try ascii_cards.getCardShortName(cards[0], self.allocator);
                defer self.allocator.free(card1_str);
                const card2_str = try ascii_cards.getCardShortName(cards[1], self.allocator);
                defer self.allocator.free(card2_str);

                if (winnings > 0) {
                    if (self.use_color) {
                        std.debug.print("{s}Player {d}: {s} {s} - WON ${d}{s}", .{ Colors.BOLD, player_index + 1, card1_str, card2_str, winnings, Colors.RESET });
                    } else {
                        std.debug.print("Player {d}: {s} {s} - WON ${d}", .{ player_index + 1, card1_str, card2_str, winnings });
                    }
                } else {
                    std.debug.print("Player {d}: {s} {s}", .{ player_index + 1, card1_str, card2_str });
                }
            } else {
                if (winnings > 0) {
                    if (self.use_color) {
                        std.debug.print("{s}Player {d}: (folded) - WON ${d}{s}", .{ Colors.BOLD, player_index + 1, winnings, Colors.RESET });
                    } else {
                        std.debug.print("Player {d}: (folded) - WON ${d}", .{ player_index + 1, winnings });
                    }
                } else {
                    if (self.use_color) {
                        std.debug.print("{s}Player {d}: (folded){s}", .{ Colors.DIM, player_index + 1, Colors.RESET });
                    } else {
                        std.debug.print("Player {d}: (folded)", .{player_index + 1});
                    }
                }
            }
            y += 1;
        }

        y += 2;
        self.moveCursor(y, center_x - 15);
        std.debug.print("{s}", .{"Press any key to continue..."});
    }
};

// Unit tests
test "table layout" {
    const testing = std.testing;

    const layout = TableLayout.init(80, 24);
    try testing.expectEqual(@as(u16, 40), layout.center_x);
    try testing.expectEqual(@as(u16, 12), layout.center_y);

    const pos = layout.getPlayerPosition(0, 4);
    try testing.expect(pos.x > 0 and pos.x < 80);
    try testing.expect(pos.y > 0 and pos.y < 24);
}

test "action history" {
    const testing = std.testing;

    var display = GameDisplay.init(testing.allocator, 80, 24, .normal, true);
    defer display.deinit();

    try display.addAction("Player1", "call", 20, .flop);
    try testing.expectEqual(@as(usize, 1), display.action_history.items.len);

    const entry = display.action_history.items[0];
    try testing.expectEqualStrings("Player1", entry.player_name);
    try testing.expectEqualStrings("call", entry.action);
    try testing.expectEqual(@as(u32, 20), entry.amount.?);
}

test "game display initialization" {
    const testing = std.testing;

    var display = GameDisplay.init(testing.allocator, 80, 24, .compact, false);
    defer display.deinit();

    try testing.expectEqual(@as(u16, 80), display.layout.width);
    try testing.expectEqual(@as(u16, 24), display.layout.height);
    try testing.expectEqual(DisplayMode.compact, display.display_mode);
    try testing.expect(!display.use_color);
}
