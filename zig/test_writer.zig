const std = @import("std");
pub fn main() !void {
    const file = try std.fs.cwd().createFile("test.txt", .{});
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    _ = try file.write("test");
}
