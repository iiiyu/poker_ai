// Regret Table Storage
// Efficient storage and manipulation of regret values with SIMD optimizations

const std = @import("std");
const builtin = @import("builtin");
const info_set = @import("info_set.zig");

// Regret precision - use f32 for memory efficiency
pub const RegretValue = f32;

// Regret entry for an information set
pub const RegretEntry = struct {
    info_set_hash: info_set.HashType,
    regrets: []RegretValue,
    num_actions: u8,
    last_update: u32,
    visit_count: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, hash: info_set.HashType, num_actions: u8) !Self {
        const regrets = try allocator.alloc(RegretValue, num_actions);
        @memset(regrets, 0.0);

        return Self{
            .info_set_hash = hash,
            .regrets = regrets,
            .num_actions = num_actions,
            .last_update = 0,
            .visit_count = 0,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.regrets);
    }

    // Apply regret floor for CFR+
    pub fn applyFloor(self: *Self, floor: RegretValue) void {
        for (self.regrets) |*regret| {
            regret.* = @max(regret.*, floor);
        }
    }

    // Get positive regrets for strategy calculation
    pub fn getPositiveRegrets(self: *Self, allocator: std.mem.Allocator) ![]RegretValue {
        const positive = try allocator.alloc(RegretValue, self.num_actions);

        // SIMD optimization for extracting positive regrets
        if (builtin.cpu.arch == .x86_64 and self.num_actions >= 4) {
            var i: usize = 0;
            const zero_vec = @as(@Vector(4, RegretValue), @splat(0.0));

            while (i + 4 <= self.num_actions) : (i += 4) {
                const regret_vec = @as(@Vector(4, RegretValue), self.regrets[i..][0..4].*);
                const positive_vec = @max(regret_vec, zero_vec);
                positive[i..][0..4].* = positive_vec;
            }

            // Handle remaining elements
            while (i < self.num_actions) : (i += 1) {
                positive[i] = @max(0.0, self.regrets[i]);
            }
        } else {
            // Scalar fallback
            for (self.regrets[0..self.num_actions], 0..) |regret, i| {
                positive[i] = @max(0.0, regret);
            }
        }

        return positive;
    }

    // Reset regrets to zero
    pub fn reset(self: *Self) void {
        @memset(self.regrets, 0.0);
        self.visit_count = 0;
    }
};

// Main regret table with sharding for parallel access
pub const RegretTable = struct {
    shards: []RegretShard,
    num_shards: usize,
    allocator: std.mem.Allocator,
    total_entries: std.atomic.Value(u64),

    const Self = @This();
    const SHARD_COUNT = 64; // More shards for better parallelism

    pub const RegretShard = struct {
        mutex: std.Thread.Mutex,
        entries: std.HashMap(info_set.HashType, RegretEntry, std.hash_map.AutoContext(info_set.HashType), std.hash_map.default_max_load_percentage),
        allocator: std.mem.Allocator,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const shards = try allocator.alloc(RegretShard, SHARD_COUNT);

        for (shards) |*shard| {
            shard.* = .{
                .mutex = std.Thread.Mutex{},
                .entries = std.HashMap(info_set.HashType, RegretEntry, std.hash_map.AutoContext(info_set.HashType), std.hash_map.default_max_load_percentage).init(allocator),
                .allocator = allocator,
            };
        }

        return Self{
            .shards = shards,
            .num_shards = SHARD_COUNT,
            .allocator = allocator,
            .total_entries = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.shards) |*shard| {
            var iterator = shard.entries.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit(shard.allocator);
            }
            shard.entries.deinit();
        }
        self.allocator.free(self.shards);
    }

    fn getShard(self: *Self, hash: info_set.HashType) *RegretShard {
        const shard_idx = hash % self.num_shards;
        return &self.shards[shard_idx];
    }

    pub fn getOrCreate(self: *Self, hash: info_set.HashType) !*RegretEntry {
        const shard = self.getShard(hash);

        shard.mutex.lock();
        defer shard.mutex.unlock();

        if (shard.entries.getPtr(hash)) |entry| {
            entry.visit_count += 1;
            return entry;
        }

        // Create new entry with default 3 actions (fold, call, raise)
        // This should be adjusted based on actual game state
        const default_actions = 3;
        const new_entry = try RegretEntry.init(shard.allocator, hash, default_actions);
        try shard.entries.put(hash, new_entry);
        _ = self.total_entries.fetchAdd(1, .monotonic);

        return shard.entries.getPtr(hash).?;
    }

    pub fn get(self: *Self, hash: info_set.HashType) ?*RegretEntry {
        const shard = self.getShard(hash);

        shard.mutex.lock();
        defer shard.mutex.unlock();

        return shard.entries.getPtr(hash);
    }

    // Batch update regrets (for SIMD efficiency)
    pub fn batchUpdateRegrets(
        self: *Self,
        updates: []const RegretUpdate,
    ) !void {
        // Group updates by shard to minimize lock contention
        var shard_updates = try self.allocator.alloc(std.ArrayList(RegretUpdate), self.num_shards);
        defer {
            for (shard_updates) |*list| {
                list.deinit();
            }
            self.allocator.free(shard_updates);
        }

        for (shard_updates) |*list| {
            list.* = std.ArrayList(RegretUpdate).init(self.allocator);
        }

        // Sort updates into shards
        for (updates) |update| {
            const shard_idx = update.hash % self.num_shards;
            try shard_updates[shard_idx].append(update);
        }

        // Apply updates to each shard
        for (self.shards, 0..) |*shard, i| {
            if (shard_updates[i].items.len == 0) continue;

            shard.mutex.lock();
            defer shard.mutex.unlock();

            for (shard_updates[i].items) |update| {
                if (shard.entries.getPtr(update.hash)) |entry| {
                    // SIMD update if possible
                    if (builtin.cpu.arch == .x86_64 and entry.num_actions >= 4) {
                        var j: usize = 0;
                        while (j + 4 <= entry.num_actions) : (j += 4) {
                            const old = @as(@Vector(4, RegretValue), entry.regrets[j..][0..4].*);
                            const delta = @as(@Vector(4, RegretValue), update.deltas[j..][0..4].*);
                            entry.regrets[j..][0..4].* = old + delta;
                        }
                        // Handle remaining
                        while (j < entry.num_actions) : (j += 1) {
                            entry.regrets[j] += update.deltas[j];
                        }
                    } else {
                        // Scalar update
                        for (entry.regrets, 0..) |*regret, j| {
                            regret.* += update.deltas[j];
                        }
                    }
                    entry.last_update = update.iteration;
                }
            }
        }
    }

    pub const RegretUpdate = struct {
        hash: info_set.HashType,
        deltas: []RegretValue,
        iteration: u32,
    };

    // Calculate average regret across all entries
    pub fn getAverageRegret(self: *Self) f32 {
        var total_regret: f64 = 0.0;
        var total_count: u64 = 0;

        for (self.shards) |*shard| {
            shard.mutex.lock();
            defer shard.mutex.unlock();

            var iterator = shard.entries.iterator();
            while (iterator.next()) |entry| {
                for (entry.value_ptr.regrets[0..entry.value_ptr.num_actions]) |regret| {
                    total_regret += @abs(regret);
                    total_count += 1;
                }
            }
        }

        if (total_count == 0) return 0.0;
        return @floatCast(total_regret / @as(f64, @floatFromInt(total_count)));
    }

    // Serialize regret table to file
    pub fn save(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        // Write header
        try writer.writeInt(u32, @intCast(self.num_shards), .little);
        const total = self.total_entries.load(.monotonic);
        try writer.writeInt(u64, total, .little);

        // Write entries from each shard
        for (self.shards) |*shard| {
            shard.mutex.lock();
            defer shard.mutex.unlock();

            try writer.writeInt(u32, @intCast(shard.entries.count()), .little);

            var iterator = shard.entries.iterator();
            while (iterator.next()) |entry| {
                // Write entry data
                try writer.writeInt(u64, entry.key_ptr.*, .little);
                try writer.writeInt(u8, entry.value_ptr.num_actions, .little);
                try writer.writeInt(u32, entry.value_ptr.last_update, .little);
                try writer.writeInt(u32, entry.value_ptr.visit_count, .little);

                // Write regrets
                for (entry.value_ptr.regrets[0..entry.value_ptr.num_actions]) |regret| {
                    try writer.writeAll(std.mem.asBytes(&regret));
                }
            }
        }

        try buffered.flush();
    }

    // Load regret table from file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buffered = std.io.bufferedReader(file.reader());
        const reader = buffered.reader();

        // Read header
        _ = try reader.readInt(u32, .little); // num_shards - not used
        const total_entries = try reader.readInt(u64, .little);

        var table = try Self.init(allocator);
        _ = table.total_entries.swap(total_entries, .monotonic);

        // Read entries for each shard
        for (table.shards) |*shard| {
            const entry_count = try reader.readInt(u32, .little);

            var i: u32 = 0;
            while (i < entry_count) : (i += 1) {
                // Read entry data
                const hash = try reader.readInt(u64, .little);
                const num_actions = try reader.readInt(u8, .little);
                const last_update = try reader.readInt(u32, .little);
                const visit_count = try reader.readInt(u32, .little);

                // Create entry
                var entry = try RegretEntry.init(shard.allocator, hash, num_actions);
                entry.last_update = last_update;
                entry.visit_count = visit_count;

                // Read regrets
                for (entry.regrets[0..num_actions]) |*regret| {
                    _ = try reader.readAll(std.mem.asBytes(regret));
                }

                try shard.entries.put(hash, entry);
            }
        }

        return table;
    }
};

// Compressed regret storage for memory efficiency
pub const CompressedRegretTable = struct {
    entries: std.HashMap(info_set.HashType, CompressedEntry, std.hash_map.AutoContext(info_set.HashType), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    compression_factor: f32,

    const Self = @This();

    pub const CompressedEntry = struct {
        // Store regrets as quantized integers for compression
        regrets: []i16, // Quantized to 16-bit
        scale: f32,
        offset: f32,
        num_actions: u8,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .entries = std.HashMap(info_set.HashType, CompressedEntry, std.hash_map.AutoContext(info_set.HashType), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .compression_factor = 10000.0, // Scale factor for quantization
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.regrets);
        }
        self.entries.deinit();
    }

    pub fn compress(self: *Self, entry: *RegretEntry) !CompressedEntry {
        // Find min and max for quantization
        var min: f32 = std.math.inf(f32);
        var max: f32 = -std.math.inf(f32);

        for (entry.regrets[0..entry.num_actions]) |regret| {
            min = @min(min, regret);
            max = @max(max, regret);
        }

        // Calculate scale and offset
        const range = max - min;
        const scale = if (range > 0) range / 32767.0 else 1.0;
        const offset = min;

        // Quantize regrets
        const compressed = try self.allocator.alloc(i16, entry.num_actions);
        for (entry.regrets[0..entry.num_actions], 0..) |regret, i| {
            const normalized = (regret - offset) / scale;
            compressed[i] = @intFromFloat(@round(normalized * 32767.0));
        }

        return CompressedEntry{
            .regrets = compressed,
            .scale = scale,
            .offset = offset,
            .num_actions = entry.num_actions,
        };
    }

    pub fn decompress(self: *Self, compressed: *CompressedEntry) !RegretEntry {
        const regrets = try self.allocator.alloc(RegretValue, compressed.num_actions);

        for (compressed.regrets[0..compressed.num_actions], 0..) |quantized, i| {
            const normalized = @as(f32, @floatFromInt(quantized)) / 32767.0;
            regrets[i] = normalized * compressed.scale + compressed.offset;
        }

        return RegretEntry{
            .info_set_hash = 0, // Will be set by caller
            .regrets = regrets,
            .num_actions = compressed.num_actions,
            .last_update = 0,
            .visit_count = 0,
        };
    }
};

// Test regret entry operations
test "regret entry initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var entry = try RegretEntry.init(allocator, 0x123456789ABCDEF0, 3);
    defer entry.deinit(allocator);

    try testing.expectEqual(@as(u8, 3), entry.num_actions);
    try testing.expectEqual(@as(RegretValue, 0.0), entry.regrets[0]);
    try testing.expectEqual(@as(u32, 0), entry.visit_count);
}

// Test positive regret extraction
test "positive regret extraction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var entry = try RegretEntry.init(allocator, 0x123456789ABCDEF0, 4);
    defer entry.deinit(allocator);

    // Set some negative and positive regrets
    entry.regrets[0] = -10.0;
    entry.regrets[1] = 5.0;
    entry.regrets[2] = -2.0;
    entry.regrets[3] = 8.0;

    const positive = try entry.getPositiveRegrets(allocator);
    defer allocator.free(positive);

    try testing.expectEqual(@as(RegretValue, 0.0), positive[0]);
    try testing.expectEqual(@as(RegretValue, 5.0), positive[1]);
    try testing.expectEqual(@as(RegretValue, 0.0), positive[2]);
    try testing.expectEqual(@as(RegretValue, 8.0), positive[3]);
}

// Test regret table operations
test "regret table basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var table = try RegretTable.init(allocator);
    defer table.deinit();

    const hash: info_set.HashType = 0x123456789ABCDEF0;

    // Get or create entry
    const entry = try table.getOrCreate(hash);
    try testing.expectEqual(@as(u8, 3), entry.num_actions);
    try testing.expectEqual(@as(u32, 1), entry.visit_count);

    // Get existing entry
    const existing = table.get(hash);
    try testing.expect(existing != null);
    try testing.expectEqual(@as(u32, 1), existing.?.visit_count);

    // Check total entries
    try testing.expectEqual(@as(u64, 1), table.total_entries.load(.monotonic));
}

// Test compression
test "regret compression and decompression" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var entry = try RegretEntry.init(allocator, 0x123456789ABCDEF0, 3);
    defer entry.deinit(allocator);

    // Set regrets with different values
    entry.regrets[0] = -100.5;
    entry.regrets[1] = 50.25;
    entry.regrets[2] = 0.0;

    var compressed_table = CompressedRegretTable.init(allocator);
    defer compressed_table.deinit();

    const compressed = try compressed_table.compress(&entry);
    defer allocator.free(compressed.regrets);

    var decompressed = try compressed_table.decompress(@constCast(&compressed));
    defer decompressed.deinit(allocator);

    // Check that values are approximately preserved
    try testing.expect(@abs(entry.regrets[0] - decompressed.regrets[0]) < 0.1);
    try testing.expect(@abs(entry.regrets[1] - decompressed.regrets[1]) < 0.1);
    try testing.expect(@abs(entry.regrets[2] - decompressed.regrets[2]) < 0.1);
}
