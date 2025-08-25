const std = @import("std");
pub fn main() !void {
    const file = try std.fs.cwd().createFile("test.txt", .{});
    defer file.close();
    
    var buffered = std.io.bufferedWriter(file.writer());
    const writer = buffered.writer();
    
    try writer.writeAll("test");
    try writer.writeInt(u32, 42, .little);
    
    try buffered.flush();
}
