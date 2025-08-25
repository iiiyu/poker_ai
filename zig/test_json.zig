const std = @import("std");
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const value = .{ .foo = "bar", .baz = 42 };
    
    var string = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer string.deinit(allocator);
    
    try std.json.Stringify.write(string.writer(), value, .{});
    std.debug.print("{s}", .{string.items});
}
