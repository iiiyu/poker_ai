//! ASCII Card Rendering
//!
//! High-performance ASCII art rendering for poker cards
//! Features:
//! - All 52 playing cards with Unicode suits
//! - ANSI color support for terminal display
//! - Compact and detailed view modes
//! - Animation helpers for card reveals
//! - Memory-efficient string operations

const std = @import("std");
const main = @import("main.zig");

pub const Card = main.Card;

/// ANSI color codes for terminal output
pub const Colors = struct {
    pub const RESET = "\x1b[0m";
    pub const RED = "\x1b[31m";
    pub const BLACK = "\x1b[30m";
    pub const WHITE = "\x1b[37m";
    pub const BOLD = "\x1b[1m";
    pub const DIM = "\x1b[2m";
    pub const BG_WHITE = "\x1b[47m";
    pub const BG_RESET = "\x1b[49m";
};

/// Unicode suit symbols
pub const Suits = struct {
    pub const SPADES = "♠";
    pub const HEARTS = "♥";
    pub const DIAMONDS = "♦";
    pub const CLUBS = "♣";
};

/// Card display modes
pub const DisplayMode = enum {
    compact, // Single character representation
    normal, // Standard 3-line card
    detailed, // Large 5-line card with borders
};

/// Get rank character for display
pub fn getRankChar(rank: u8) u8 {
    return switch (rank) {
        0 => '2',
        1 => '3',
        2 => '4',
        3 => '5',
        4 => '6',
        5 => '7',
        6 => '8',
        7 => '9',
        8 => 'T',
        9 => 'J',
        10 => 'Q',
        11 => 'K',
        12 => 'A',
        else => '?',
    };
}

/// Get rank string for display
pub fn getRankString(rank: u8, allocator: std.mem.Allocator) ![]u8 {
    return switch (rank) {
        0...8 => try std.fmt.allocPrint(allocator, "{c}", .{getRankChar(rank)}),
        9 => try allocator.dupe(u8, "J"),
        10 => try allocator.dupe(u8, "Q"),
        11 => try allocator.dupe(u8, "K"),
        12 => try allocator.dupe(u8, "A"),
        else => try allocator.dupe(u8, "?"),
    };
}

/// Get suit symbol
pub fn getSuitSymbol(suit: u8) []const u8 {
    return switch (suit) {
        0 => Suits.CLUBS,
        1 => Suits.DIAMONDS,
        2 => Suits.HEARTS,
        3 => Suits.SPADES,
        else => "?",
    };
}

/// Get suit color for terminal display
pub fn getSuitColor(suit: u8) []const u8 {
    return switch (suit) {
        0, 3 => Colors.BLACK, // Clubs and Spades (black)
        1, 2 => Colors.RED, // Diamonds and Hearts (red)
        else => Colors.RESET,
    };
}

/// Convert card to rank and suit
pub fn cardToRankSuit(card: Card) struct { rank: u8, suit: u8 } {
    return .{
        .rank = card >> 2, // Upper 6 bits
        .suit = card & 3, // Lower 2 bits
    };
}

/// Render card in compact mode (single character)
pub fn renderCompact(card: Card, allocator: std.mem.Allocator) ![]u8 {
    const rs = cardToRankSuit(card);
    const rank_char = getRankChar(rs.rank);
    const color = getSuitColor(rs.suit);

    return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ color, rank_char, Colors.RESET });
}

/// Render card in normal mode (3 lines)
pub fn renderNormal(card: Card, allocator: std.mem.Allocator) ![]u8 {
    const rs = cardToRankSuit(card);
    const rank_char = getRankChar(rs.rank);
    const color = getSuitColor(rs.suit);

    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    // Top line: ┌─────┐
    try result.appendSlice(allocator, "┌─────┐\n");

    // Middle line: |A♠   |
    try result.writer(allocator).print("│{s}{c}{s}   │\n", .{ color, rank_char, Colors.RESET });

    // Bottom line: └─────┘
    try result.appendSlice(allocator, "└─────┘");

    return result.toOwnedSlice(allocator);
}

/// Render card in detailed mode (5 lines)
pub fn renderDetailed(card: Card, allocator: std.mem.Allocator) ![]u8 {
    const rs = cardToRankSuit(card);
    const rank_char = getRankChar(rs.rank);
    const suit_symbol = getSuitSymbol(rs.suit);
    const color = getSuitColor(rs.suit);

    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    // Top border
    try result.appendSlice(allocator, "┌───────┐\n");

    // Rank and suit (top)
    try result.writer(allocator).print("│{s}{c}     {s}│\n", .{ color, rank_char, Colors.RESET });

    // Center suit symbol
    try result.writer(allocator).print("│  {s}{s}{s}  │\n", .{ color, suit_symbol, Colors.RESET });

    // Rank and suit (bottom, inverted)
    try result.writer(allocator).print("│{s}     {c}{s}│\n", .{ color, rank_char, Colors.RESET });

    // Bottom border
    try result.appendSlice(allocator, "└───────┘");

    return result.toOwnedSlice(allocator);
}

/// Render card face down
pub fn renderFaceDown(mode: DisplayMode, allocator: std.mem.Allocator) ![]u8 {
    return switch (mode) {
        .compact => try allocator.dupe(u8, "?"),
        .normal => try allocator.dupe(u8, "┌─────┐\n│ ??? │\n└─────┘"),
        .detailed => try allocator.dupe(u8, "┌───────┐\n│ ????? │\n│  ???  │\n│ ????? │\n└───────┘"),
    };
}

/// Render multiple cards side by side
pub fn renderMultipleCards(cards: []const Card, mode: DisplayMode, allocator: std.mem.Allocator) ![]u8 {
    if (cards.len == 0) return try allocator.dupe(u8, "");

    switch (mode) {
        .compact => {
            var result = try std.ArrayList(u8).initCapacity(allocator, 0);
            defer result.deinit(allocator);

            for (cards, 0..) |card, i| {
                if (i > 0) try result.appendSlice(allocator, " ");
                const card_str = try renderCompact(card, allocator);
                defer allocator.free(card_str);
                try result.appendSlice(allocator, card_str);
            }

            return result.toOwnedSlice(allocator);
        },
        .normal, .detailed => {
            // Render each card and then combine line by line
            var card_renders = try std.ArrayList([]u8).initCapacity(allocator, 0);
            defer {
                for (card_renders.items) |render| {
                    allocator.free(render);
                }
                card_renders.deinit(allocator);
            }

            for (cards) |card| {
                const render = if (mode == .normal)
                    try renderNormal(card, allocator)
                else
                    try renderDetailed(card, allocator);
                try card_renders.append(allocator, render);
            }

            // Split each render into lines
            var all_lines = try std.ArrayList([][]const u8).initCapacity(allocator, 0);
            defer {
                for (all_lines.items) |lines| {
                    allocator.free(lines);
                }
                all_lines.deinit(allocator);
            }

            for (card_renders.items) |render| {
                var lines = try std.ArrayList([]const u8).initCapacity(allocator, 0);
                defer lines.deinit(allocator);

                var line_iter = std.mem.splitScalar(u8, render, '\n');
                while (line_iter.next()) |line| {
                    try lines.append(allocator, line);
                }

                try all_lines.append(allocator, try lines.toOwnedSlice(allocator));
            }

            // Combine lines horizontally
            var result = try std.ArrayList(u8).initCapacity(allocator, 0);
            defer result.deinit(allocator);

            if (all_lines.items.len > 0) {
                const num_lines = all_lines.items[0].len;

                for (0..num_lines) |line_idx| {
                    for (all_lines.items, 0..) |card_lines, card_idx| {
                        if (card_idx > 0) try result.appendSlice(allocator, " ");
                        if (line_idx < card_lines.len) {
                            try result.appendSlice(allocator, card_lines[line_idx]);
                        }
                    }
                    if (line_idx < num_lines - 1) try result.appendSlice(allocator, "\n");
                }
            }

            return result.toOwnedSlice(allocator);
        },
    }
}

/// Animation frame for card reveal
pub const RevealFrame = struct {
    card: Card,
    reveal_progress: f32, // 0.0 = face down, 1.0 = fully revealed

    pub fn render(self: RevealFrame, mode: DisplayMode, allocator: std.mem.Allocator) ![]u8 {
        if (self.reveal_progress < 0.5) {
            return renderFaceDown(mode, allocator);
        } else {
            return switch (mode) {
                .compact => renderCompact(self.card, allocator),
                .normal => renderNormal(self.card, allocator),
                .detailed => renderDetailed(self.card, allocator),
            };
        }
    }
};

/// Card hand display helper
pub const HandDisplay = struct {
    cards: []const Card,
    mode: DisplayMode,
    allocator: std.mem.Allocator,

    pub fn init(cards: []const Card, mode: DisplayMode, allocator: std.mem.Allocator) HandDisplay {
        return HandDisplay{
            .cards = cards,
            .mode = mode,
            .allocator = allocator,
        };
    }

    pub fn render(self: HandDisplay) ![]u8 {
        return renderMultipleCards(self.cards, self.mode, self.allocator);
    }

    pub fn renderWithLabel(self: HandDisplay, label: []const u8) ![]u8 {
        const cards_str = try self.render();
        defer self.allocator.free(cards_str);

        return try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ label, cards_str });
    }
};

/// Get card short name (e.g., "As", "Kh", "2c")
pub fn getCardShortName(card: Card, allocator: std.mem.Allocator) ![]u8 {
    const rs = cardToRankSuit(card);
    const rank_char = getRankChar(rs.rank);
    const suit_char = switch (rs.suit) {
        0 => 'c', // Clubs
        1 => 'd', // Diamonds
        2 => 'h', // Hearts
        3 => 's', // Spades
        else => '?',
    };

    return try std.fmt.allocPrint(allocator, "{c}{c}", .{ rank_char, suit_char });
}

/// Parse card from short name (e.g., "As" -> Ace of Spades)
pub fn parseCardShortName(name: []const u8) !Card {
    if (name.len != 2) return error.InvalidCardName;

    const rank = switch (name[0]) {
        '2' => @as(u8, 0),
        '3' => @as(u8, 1),
        '4' => @as(u8, 2),
        '5' => @as(u8, 3),
        '6' => @as(u8, 4),
        '7' => @as(u8, 5),
        '8' => @as(u8, 6),
        '9' => @as(u8, 7),
        'T', 't' => @as(u8, 8),
        'J', 'j' => @as(u8, 9),
        'Q', 'q' => @as(u8, 10),
        'K', 'k' => @as(u8, 11),
        'A', 'a' => @as(u8, 12),
        else => return error.InvalidRank,
    };

    const suit = switch (name[1]) {
        'c', 'C' => @as(u8, 0), // Clubs
        'd', 'D' => @as(u8, 1), // Diamonds
        'h', 'H' => @as(u8, 2), // Hearts
        's', 'S' => @as(u8, 3), // Spades
        else => return error.InvalidSuit,
    };

    return (rank << 2) | suit;
}

/// Terminal screen clearing and cursor control
pub const Screen = struct {
    pub const CLEAR_SCREEN = "\x1b[2J";
    pub const MOVE_CURSOR_HOME = "\x1b[H";
    pub const HIDE_CURSOR = "\x1b[?25l";
    pub const SHOW_CURSOR = "\x1b[?25h";

    pub fn clear() void {
        std.debug.print("{s}{s}", .{ CLEAR_SCREEN, MOVE_CURSOR_HOME });
    }

    pub fn hideCursor() void {
        std.debug.print("{s}", .{HIDE_CURSOR});
    }

    pub fn showCursor() void {
        std.debug.print("{s}", .{SHOW_CURSOR});
    }

    pub fn moveTo(row: u16, col: u16) void {
        std.debug.print("\x1b[{d};{d}H", .{ row, col });
    }
};

// Unit tests
test "card rank and suit conversion" {
    const testing = std.testing;

    // Test Ace of Spades (card value 51)
    const ace_spades: Card = (12 << 2) | 3; // rank 12, suit 3
    const rs = cardToRankSuit(ace_spades);

    try testing.expectEqual(@as(u8, 12), rs.rank);
    try testing.expectEqual(@as(u8, 3), rs.suit);
    try testing.expectEqual(@as(u8, 'A'), getRankChar(rs.rank));
    try testing.expectEqualStrings(Suits.SPADES, getSuitSymbol(rs.suit));
}

test "card parsing" {
    const testing = std.testing;

    const ace_spades = try parseCardShortName("As");
    const rs = cardToRankSuit(ace_spades);

    try testing.expectEqual(@as(u8, 12), rs.rank); // Ace
    try testing.expectEqual(@as(u8, 3), rs.suit); // Spades

    try testing.expectError(error.InvalidCardName, parseCardShortName("A"));
    try testing.expectError(error.InvalidRank, parseCardShortName("Xs"));
    try testing.expectError(error.InvalidSuit, parseCardShortName("Ax"));
}

test "card short name generation" {
    const testing = std.testing;

    const ace_spades: Card = (12 << 2) | 3;
    const name = try getCardShortName(ace_spades, testing.allocator);
    defer testing.allocator.free(name);

    try testing.expectEqualStrings("As", name);
}

test "card rendering modes" {
    const testing = std.testing;

    const ace_spades: Card = (12 << 2) | 3;

    // Test compact mode
    const compact = try renderCompact(ace_spades, testing.allocator);
    defer testing.allocator.free(compact);
    try testing.expect(compact.len > 0);

    // Test normal mode
    const normal = try renderNormal(ace_spades, testing.allocator);
    defer testing.allocator.free(normal);
    try testing.expect(std.mem.indexOf(u8, normal, "A") != null);

    // Test detailed mode
    const detailed = try renderDetailed(ace_spades, testing.allocator);
    defer testing.allocator.free(detailed);
    try testing.expect(std.mem.indexOf(u8, detailed, "A") != null);
}

test "multiple cards rendering" {
    const testing = std.testing;

    const cards = [_]Card{
        (12 << 2) | 3, // Ace of Spades
        (11 << 2) | 2, // King of Hearts
    };

    const result = try renderMultipleCards(&cards, .compact, testing.allocator);
    defer testing.allocator.free(result);

    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, " ") != null); // Should have separator
}

test "hand display" {
    const testing = std.testing;

    const cards = [_]Card{
        (12 << 2) | 3, // Ace of Spades
        (11 << 2) | 2, // King of Hearts
    };

    const hand = HandDisplay.init(&cards, .compact, testing.allocator);
    const result = try hand.render();
    defer testing.allocator.free(result);

    try testing.expect(result.len > 0);

    const labeled = try hand.renderWithLabel("Hole Cards");
    defer testing.allocator.free(labeled);

    try testing.expect(std.mem.indexOf(u8, labeled, "Hole Cards") != null);
}
