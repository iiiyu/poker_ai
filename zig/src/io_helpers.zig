// Helper functions for file I/O in Zig 0.15.1
const std = @import("std");

/// Write an integer to a file in little-endian format
pub fn writeInt(file: std.fs.File, comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try file.writeAll(&bytes);
}

/// Read an integer from a file in little-endian format  
pub fn readInt(file: std.fs.File, comptime T: type) !T {
    var bytes: [@sizeOf(T)]u8 = undefined;
    const bytes_read = try file.read(&bytes);
    if (bytes_read != bytes.len) return error.EndOfStream;
    return std.mem.readInt(T, &bytes, .little);
}

/// Write an integer in big-endian format
pub fn writeIntBig(file: std.fs.File, comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .big);
    try file.writeAll(&bytes);
}

/// Read an integer in big-endian format
pub fn readIntBig(file: std.fs.File, comptime T: type) !T {
    var bytes: [@sizeOf(T)]u8 = undefined;
    const bytes_read = try file.read(&bytes);
    if (bytes_read != bytes.len) return error.EndOfStream;
    return std.mem.readInt(T, &bytes, .big);
}