const std = @import("std");
pub fn main() !void {
    const stdout = std.fs.File.stdout();
    _ = try stdout.write("test");
}
