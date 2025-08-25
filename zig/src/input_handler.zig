//! Input Handler
//! 
//! Non-blocking keyboard input processing for terminal UI
//! Features:
//! - Cross-platform terminal input handling
//! - Action selection (fold/call/raise/check)
//! - Bet sizing input with validation
//! - Menu navigation support
//! - Timeout handling for AI turns

const std = @import("std");
const builtin = @import("builtin");

/// Player action types
pub const ActionType = enum {
    fold,
    check,
    call,
    raise,
    all_in,
    quit,
    invalid,
    
    pub fn toString(self: ActionType) []const u8 {
        return switch (self) {
            .fold => "fold",
            .check => "check", 
            .call => "call",
            .raise => "raise",
            .all_in => "all-in",
            .quit => "quit",
            .invalid => "invalid",
        };
    }
};

/// Menu actions
pub const MenuAction = enum {
    up,
    down,
    select,
    back,
    quit,
    invalid,
};

/// Input event types
pub const InputEvent = union(enum) {
    player_action: struct {
        action: ActionType,
        amount: ?u32, // For raise amounts
    },
    menu_action: MenuAction,
    raw_key: u8,
    timeout,
    input_error: anyerror,
};

/// Terminal configuration for input handling
const TerminalConfig = struct {
    // Store original terminal settings for restoration
    original_settings: if (builtin.os.tag == .windows) void else std.posix.termios,
    
    fn enableRawMode(self: *TerminalConfig) !void {
        if (builtin.os.tag == .windows) {
            // Windows implementation would use SetConsoleMode
            // For now, skip on Windows
            return;
        } else {
            // Get current terminal settings
            self.original_settings = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
            
            // Create new settings for raw mode
            var raw_settings = self.original_settings;
            
            // Disable canonical mode (line buffering) and echo
            raw_settings.lflag.ICANON = false;
            raw_settings.lflag.ECHO = false;
            raw_settings.lflag.ISIG = false;  // Disable signal generation (Ctrl+C, etc.)
            
            // Disable input processing  
            raw_settings.iflag.IXON = false;   // Disable XON/XOFF flow control
            raw_settings.iflag.ICRNL = false;  // Don't translate CR to NL
            raw_settings.iflag.INPCK = false;  // Disable parity checking
            raw_settings.iflag.ISTRIP = false; // Don't strip 8th bit
            
            // Disable output processing
            raw_settings.oflag.OPOST = false;
            
            // Set character size to 8 bits
            raw_settings.cflag.CSIZE = .CS8;
            
            // Set read timeout: return immediately if no input
            raw_settings.cc[@intFromEnum(std.posix.V.TIME)] = 0;
            raw_settings.cc[@intFromEnum(std.posix.V.MIN)] = 0;
            
            // Apply the settings
            try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw_settings);
        }
    }
    
    fn restoreMode(self: *TerminalConfig) !void {
        if (builtin.os.tag == .windows) {
            // Windows implementation would restore console mode
            return;
        } else {
            // Restore original terminal settings
            try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, self.original_settings);
        }
    }
};

/// Input handler state
pub const InputHandler = struct {
    allocator: std.mem.Allocator,
    terminal_config: TerminalConfig,
    is_raw_mode: bool,
    
    pub fn init(allocator: std.mem.Allocator) InputHandler {
        return InputHandler{
            .allocator = allocator,
            .terminal_config = TerminalConfig{
                .original_settings = undefined,
            },
            .is_raw_mode = false,
        };
    }
    
    pub fn enableRawMode(self: *InputHandler) !void {
        if (!self.is_raw_mode) {
            try self.terminal_config.enableRawMode();
            self.is_raw_mode = true;
        }
    }
    
    pub fn restoreMode(self: *InputHandler) !void {
        if (self.is_raw_mode) {
            try self.terminal_config.restoreMode();
            self.is_raw_mode = false;
        }
    }
    
    pub fn deinit(self: *InputHandler) void {
        self.restoreMode() catch {};
    }
    
    /// Read a single character without blocking
    pub fn readChar(self: *InputHandler) !?u8 {
        if (!self.is_raw_mode) {
            // If not in raw mode, don't try to read
            return null;
        }
        
        if (builtin.os.tag == .windows) {
            // Windows implementation would use _kbhit() and _getch()
            // For now, return null (no input available)
            return null;
        } else {
            var buffer: [1]u8 = undefined;
            
            // The terminal is already in raw mode with VMIN=0 and VTIME=0
            // This makes read() non-blocking
            const bytes_read = std.posix.read(std.posix.STDIN_FILENO, &buffer) catch |err| switch (err) {
                error.WouldBlock => return null,
                else => return err,
            };
            
            if (bytes_read == 0) return null;
            return buffer[0];
        }
    }
    
    /// Read input with timeout (milliseconds)
    pub fn readWithTimeout(self: *InputHandler, timeout_ms: u32) !?u8 {
        const start_time = std.time.milliTimestamp();
        
        while (true) {
            if (try self.readChar()) |char| {
                return char;
            }
            
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed >= timeout_ms) {
                return null; // Timeout
            }
            
            // Small delay to prevent busy waiting
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }
    
    /// Parse player action from character input
    pub fn parsePlayerAction(self: *InputHandler, char: u8) ActionType {
        _ = self;
        return switch (char) {
            'f', 'F' => .fold,
            'c', 'C' => .call,
            'k', 'K' => .check,
            'r', 'R' => .raise,
            'a', 'A' => .all_in,
            'q', 'Q' => .quit,
            27 => .quit, // ESC key
            else => .invalid,
        };
    }
    
    /// Parse menu action from character input
    pub fn parseMenuAction(self: *InputHandler, char: u8) MenuAction {
        _ = self;
        return switch (char) {
            'w', 'W' => .up,    // W key
            's', 'S' => .down,  // S key
            '\r', '\n', ' ' => .select, // Enter or Space
            'b', 'B' => .back,  // B key
            27 => .back,   // ESC key (plain ESC, not arrow sequence)
            'q', 'Q' => .quit,
            else => .invalid,
        };
    }
    
    /// Get key input and convert to InputEvent
    pub fn getKeyInput(self: *InputHandler) !InputEvent {
        if (try self.readChar()) |char| {
            // Handle arrow key sequences
            if (char == 27) { // ESC sequence start
                if (try self.readChar()) |second| {
                    if (second == 91) { // '[' for arrow keys
                        if (try self.readChar()) |third| {
                            return InputEvent{ .menu_action = switch (third) {
                                65 => .up,    // Up arrow
                                66 => .down,  // Down arrow
                                67 => .select, // Right arrow (treat as select)
                                68 => .back,  // Left arrow (treat as back)
                                else => .invalid,
                            }};
                        }
                    }
                }
                return InputEvent{ .menu_action = .back }; // Plain ESC
            }
            
            const menu_action = self.parseMenuAction(char);
            if (menu_action != .invalid) {
                return InputEvent{ .menu_action = menu_action };
            }
            
            const player_action = self.parsePlayerAction(char);
            if (player_action != .invalid) {
                return InputEvent{ .player_action = .{ .action = player_action, .amount = null } };
            }
            
            return InputEvent{ .raw_key = char };
        }
        
        return InputEvent{ .timeout = {} };
    }
    
    /// Get raise amount input with +/- controls
    pub fn getRaiseAmountInput(
        self: *InputHandler,
        current_amount: u32,
        min_amount: u32,
        max_amount: u32
    ) !InputEvent {
        if (try self.readChar()) |char| {
            switch (char) {
                '+', '=' => {
                    const increment = @max(10, (max_amount - min_amount) / 20);
                    const new_amount = @min(max_amount, current_amount + increment);
                    return InputEvent{ .player_action = .{ .action = .raise, .amount = new_amount } };
                },
                '-', '_' => {
                    const decrement = @max(10, (max_amount - min_amount) / 20);
                    const new_amount = @max(min_amount, current_amount - decrement);
                    return InputEvent{ .player_action = .{ .action = .raise, .amount = new_amount } };
                },
                '\r', '\n' => {
                    return InputEvent{ .menu_action = .select };
                },
                '\x08', '\x7f' => { // Backspace or DEL
                    return InputEvent{ .menu_action = .back };
                },
                'q', 'Q', 27 => {
                    return InputEvent{ .menu_action = .quit };
                },
                else => {}
            }
            
            return InputEvent{ .raw_key = char };
        }
        
        return InputEvent{ .timeout = {} };
    }
    
    /// Check for quit input without blocking
    pub fn checkForQuit(self: *InputHandler) !bool {
        if (try self.readChar()) |char| {
            return char == 'q' or char == 'Q' or char == 27; // q, Q, or ESC
        }
        return false;
    }
    
    /// Wait for any key press with optional message
    pub fn waitForAnyKey(self: *InputHandler, message: ?[]const u8) !void {
        if (message) |msg| {
            std.debug.print("{s}", .{msg});
        }
        
        while (true) {
            if (try self.readChar()) |_| {
                break;
            }
            std.time.sleep(50 * std.time.ns_per_ms); // 50ms delay
        }
    }
    
    /// Get player action with menu display
    pub fn getPlayerAction(
        self: *InputHandler,
        available_actions: []const ActionType,
        _: u32, // current_bet unused
        call_amount: u32,
        min_raise: u32,
        max_raise: u32,
        timeout_ms: ?u32
    ) !InputEvent {
        // Display available actions
        std.debug.print("\n--- Your Action ---\n");
        for (available_actions, 0..) |action, i| {
            const key = switch (action) {
                .fold => "[F]old",
                .check => "[C]heck",
                .call => try std.fmt.allocPrint(self.allocator, "[C]all {d}", .{call_amount}),
                .raise => try std.fmt.allocPrint(self.allocator, "[R]aise (min: {d}, max: {d})", .{ min_raise, max_raise }),
                .all_in => try std.fmt.allocPrint(self.allocator, "[A]ll-in ({d})", .{max_raise}),
                .quit => "[Q]uit",
                else => continue,
            };
            defer if (action == .call or action == .raise or action == .all_in) {
                self.allocator.free(key);
            };
            
            std.debug.print("  {d}. {s}\n", .{ i + 1, key });
        }
        std.debug.print("Choice: ");
        
        // Read input with optional timeout
        const char = if (timeout_ms) |timeout| 
            try self.readWithTimeout(timeout) 
        else 
            try self.readChar();
            
        if (char == null) {
            return InputEvent{ .timeout = {} };
        }
        
        const action = self.parsePlayerAction(char.?);
        
        // Validate action is available
        var is_valid = false;
        for (available_actions) |available| {
            if (available == action) {
                is_valid = true;
                break;
            }
        }
        
        if (!is_valid) {
            return InputEvent{ 
                .player_action = .{ 
                    .action = .invalid, 
                    .amount = null 
                } 
            };
        }
        
        // Handle raise amount input
        if (action == .raise) {
            std.debug.print("\nRaise amount ({d}-{d}): ", .{ min_raise, max_raise });
            
            const amount = try self.getRaiseAmount(min_raise, max_raise);
            if (amount == null) {
                return InputEvent{ 
                    .player_action = .{ 
                        .action = .invalid, 
                        .amount = null 
                    } 
                };
            }
            
            return InputEvent{ 
                .player_action = .{ 
                    .action = action, 
                    .amount = amount 
                } 
            };
        }
        
        return InputEvent{ 
            .player_action = .{ 
                .action = action, 
                .amount = null 
            } 
        };
    }
    
    /// Get raise amount from user input
    pub fn getRaiseAmount(self: *InputHandler, min_amount: u32, max_amount: u32) !?u32 {
        _ = self; // Remove unused variable warning for now
        
        // For now, we'll use a simple approach and read from stdin
        // In a full implementation, this would use the raw input system
        
        var buffer: [32]u8 = undefined;
        
        if (try std.io.getStdIn().readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \t\r\n");
            
            if (trimmed.len == 0) return null;
            
            const amount = std.fmt.parseInt(u32, trimmed, 10) catch {
                std.debug.print("Invalid amount. Please enter a number.\n");
                return null;
            };
            
            if (amount < min_amount or amount > max_amount) {
                std.debug.print("Amount must be between {d} and {d}.\n", .{ min_amount, max_amount });
                return null;
            }
            
            return amount;
        }
        
        return null;
    }
    
    /// Handle menu navigation
    pub fn handleMenu(
        self: *InputHandler,
        menu_items: []const []const u8,
        selected_index: *usize,
        timeout_ms: ?u32
    ) !InputEvent {
        // Use getKeyInput for proper escape sequence handling
        const input_event = if (timeout_ms) |timeout| blk: {
            const char = try self.readWithTimeout(timeout);
            if (char == null) {
                break :blk InputEvent{ .timeout = {} };
            }
            
            // Handle arrow key sequences
            if (char.? == 27) { // ESC sequence start
                if (try self.readChar()) |second| {
                    if (second == 91) { // '[' for arrow keys
                        if (try self.readChar()) |third| {
                            break :blk InputEvent{ .menu_action = switch (third) {
                                65 => .up,    // Up arrow
                                66 => .down,  // Down arrow
                                67 => .select, // Right arrow (treat as select)
                                68 => .back,  // Left arrow (treat as back)
                                else => .invalid,
                            }};
                        }
                    }
                }
                break :blk InputEvent{ .menu_action = .back }; // Plain ESC
            }
            
            const menu_action = self.parseMenuAction(char.?);
            if (menu_action != .invalid) {
                break :blk InputEvent{ .menu_action = menu_action };
            }
            
            // Check if it's a number key for direct selection
            if (char.? >= '1' and char.? <= '9') {
                const index = char.? - '1';
                if (index < menu_items.len) {
                    selected_index.* = index;
                    break :blk InputEvent{ .menu_action = .select };
                }
            }
            
            break :blk InputEvent{ .menu_action = .invalid };
        } else blk: {
            break :blk try self.getKeyInput();
        };
        
        switch (input_event) {
            .menu_action => |menu_action| {
                switch (menu_action) {
                    .up => {
                        if (selected_index.* > 0) {
                            selected_index.* -= 1;
                        } else {
                            selected_index.* = menu_items.len - 1; // Wrap to bottom
                        }
                        return InputEvent{ .menu_action = menu_action };
                    },
                    .down => {
                        if (selected_index.* < menu_items.len - 1) {
                            selected_index.* += 1;
                        } else {
                            selected_index.* = 0; // Wrap to top
                        }
                        return InputEvent{ .menu_action = menu_action };
                    },
                    .select, .back, .quit => {
                        return InputEvent{ .menu_action = menu_action };
                    },
                    .invalid => {
                        return InputEvent{ .menu_action = .invalid };
                    },
                }
            },
            .raw_key => |char| {
                // Handle number keys for direct selection
                if (char >= '1' and char <= '9') {
                    const index = char - '1';
                    if (index < menu_items.len) {
                        selected_index.* = index;
                        return InputEvent{ .menu_action = .select };
                    }
                }
                return InputEvent{ .menu_action = .invalid };
            },
            .timeout => {
                return InputEvent{ .timeout = {} };
            },
            else => {
                return InputEvent{ .menu_action = .invalid };
            },
        }
    }
    
    /// Get yes/no confirmation
    pub fn getConfirmation(self: *InputHandler, prompt: []const u8) !bool {
        std.debug.print("{s} (y/n): ", .{prompt});
        
        while (true) {
            if (try self.readChar()) |char| {
                switch (char) {
                    'y', 'Y' => {
                        std.debug.print("Yes\n");
                        return true;
                    },
                    'n', 'N' => {
                        std.debug.print("No\n");
                        return false;
                    },
                    else => continue,
                }
            }
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }
};

/// Helper functions for action validation
pub fn isActionAvailable(action: ActionType, available_actions: []const ActionType) bool {
    for (available_actions) |available| {
        if (available == action) return true;
    }
    return false;
}

/// Get available actions based on game state
pub fn getAvailableActions(
    allocator: std.mem.Allocator,
    can_check: bool,
    can_call: bool,
    can_raise: bool,
    can_fold: bool
) ![]ActionType {
    var actions = std.ArrayList(ActionType).init(allocator);
    defer actions.deinit();
    
    if (can_fold) try actions.append(.fold);
    if (can_check) try actions.append(.check);
    if (can_call) try actions.append(.call);
    if (can_raise) {
        try actions.append(.raise);
        try actions.append(.all_in);
    }
    try actions.append(.quit);
    
    return actions.toOwnedSlice();
}

// Unit tests
test "action parsing" {
    const testing = std.testing;
    
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();
    
    try testing.expectEqual(ActionType.fold, handler.parsePlayerAction('f'));
    try testing.expectEqual(ActionType.call, handler.parsePlayerAction('c'));
    try testing.expectEqual(ActionType.raise, handler.parsePlayerAction('r'));
    try testing.expectEqual(ActionType.quit, handler.parsePlayerAction('q'));
    try testing.expectEqual(ActionType.invalid, handler.parsePlayerAction('x'));
}

test "menu action parsing" {
    const testing = std.testing;
    
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();
    
    try testing.expectEqual(MenuAction.up, handler.parseMenuAction('w'));
    try testing.expectEqual(MenuAction.down, handler.parseMenuAction('s'));
    try testing.expectEqual(MenuAction.select, handler.parseMenuAction('\n'));
    try testing.expectEqual(MenuAction.back, handler.parseMenuAction('b'));
    try testing.expectEqual(MenuAction.quit, handler.parseMenuAction('q'));
    try testing.expectEqual(MenuAction.invalid, handler.parseMenuAction('x'));
}

test "action availability" {
    const testing = std.testing;
    
    const available = [_]ActionType{ .fold, .call, .raise };
    
    try testing.expect(isActionAvailable(.fold, &available));
    try testing.expect(isActionAvailable(.call, &available));
    try testing.expect(isActionAvailable(.raise, &available));
    try testing.expect(!isActionAvailable(.check, &available));
}

test "input handler initialization" {
    const testing = std.testing;
    
    var handler = InputHandler.init(testing.allocator);
    defer handler.deinit();
    
    try testing.expect(!handler.is_raw_mode);
}