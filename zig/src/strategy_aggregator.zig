// Strategy Aggregation
// Lock-free strategy aggregation with SIMD optimizations

const std = @import("std");
const builtin = @import("builtin");
const info_set = @import("info_set.zig");
const regret_table = @import("regret_table.zig");

// Strategy value type
pub const StrategyValue = f32;

// Strategy entry for an information set
pub const StrategyEntry = struct {
    info_set_hash: info_set.HashType,
    strategy_sum: []StrategyValue,
    current_strategy: []StrategyValue,
    num_actions: u8,
    total_weight: f64,
    iterations: u32,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, hash: info_set.HashType, num_actions: u8) !Self {
        const strategy_sum = try allocator.alloc(StrategyValue, num_actions);
        const current_strategy = try allocator.alloc(StrategyValue, num_actions);
        
        // Initialize with uniform strategy
        const uniform = 1.0 / @as(StrategyValue, @floatFromInt(num_actions));
        @memset(strategy_sum, 0.0);
        @memset(current_strategy, uniform);
        
        return Self{
            .info_set_hash = hash,
            .strategy_sum = strategy_sum,
            .current_strategy = current_strategy,
            .num_actions = num_actions,
            .total_weight = 0.0,
            .iterations = 0,
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.strategy_sum);
        allocator.free(self.current_strategy);
    }
    
    // Update strategy sum with weighted contribution
    pub fn updateSum(self: *Self, strategy: []const StrategyValue, weight: f64) void {
        std.debug.assert(strategy.len == self.num_actions);
        
        // SIMD-optimized update
        if (builtin.cpu.arch == .x86_64 and self.num_actions >= 4) {
            const weight_vec = @as(@Vector(4, StrategyValue), @splat(@floatCast(weight)));
            var i: usize = 0;
            
            while (i + 4 <= self.num_actions) : (i += 4) {
                const strat_vec = @as(@Vector(4, StrategyValue), strategy[i..][0..4].*);
                const sum_vec = @as(@Vector(4, StrategyValue), self.strategy_sum[i..][0..4].*);
                self.strategy_sum[i..][0..4].* = sum_vec + (strat_vec * weight_vec);
            }
            
            // Handle remaining elements
            while (i < self.num_actions) : (i += 1) {
                self.strategy_sum[i] += strategy[i] * @as(StrategyValue, @floatCast(weight));
            }
        } else {
            // Scalar fallback
            for (strategy[0..self.num_actions], 0..) |prob, i| {
                self.strategy_sum[i] += prob * @as(StrategyValue, @floatCast(weight));
            }
        }
        
        self.total_weight += weight;
        self.iterations += 1;
    }
    
    // Get average strategy
    pub fn getAverageStrategy(self: *Self) []StrategyValue {
        if (self.total_weight <= 0.0) {
            // Return uniform strategy if no weight accumulated
            const uniform = 1.0 / @as(StrategyValue, @floatFromInt(self.num_actions));
            @memset(self.current_strategy, uniform);
            return self.current_strategy;
        }
        
        const inv_weight = 1.0 / @as(StrategyValue, @floatCast(self.total_weight));
        
        // SIMD-optimized division
        if (builtin.cpu.arch == .x86_64 and self.num_actions >= 4) {
            const inv_weight_vec = @as(@Vector(4, StrategyValue), @splat(inv_weight));
            var i: usize = 0;
            
            while (i + 4 <= self.num_actions) : (i += 4) {
                const sum_vec = @as(@Vector(4, StrategyValue), self.strategy_sum[i..][0..4].*);
                self.current_strategy[i..][0..4].* = sum_vec * inv_weight_vec;
            }
            
            // Handle remaining elements
            while (i < self.num_actions) : (i += 1) {
                self.current_strategy[i] = self.strategy_sum[i] * inv_weight;
            }
        } else {
            // Scalar fallback
            for (self.strategy_sum[0..self.num_actions], 0..) |sum, i| {
                self.current_strategy[i] = sum * inv_weight;
            }
        }
        
        return self.current_strategy;
    }
};

// Lock-free strategy aggregator using atomic operations
pub const StrategyAggregator = struct {
    shards: []StrategyShard,
    num_shards: usize,
    allocator: std.mem.Allocator,
    total_strategies: std.atomic.Value(u64),
    
    const Self = @This();
    const SHARD_COUNT = 32;
    
    pub const StrategyShard = struct {
        // Use RwLock for better read performance
        rwlock: std.Thread.RwLock,
        entries: std.HashMap(info_set.HashType, StrategyEntry, std.hash_map.AutoContext(info_set.HashType), std.hash_map.default_max_load_percentage),
        allocator: std.mem.Allocator,
        
        // Statistics
        updates: std.atomic.Value(u64),
        queries: std.atomic.Value(u64),
    };
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        const shards = try allocator.alloc(StrategyShard, SHARD_COUNT);
        
        for (shards) |*shard| {
            shard.* = .{
                .rwlock = std.Thread.RwLock{},
                .entries = std.HashMap(
                    info_set.HashType,
                    StrategyEntry,
                    std.hash_map.AutoContext(info_set.HashType),
                    std.hash_map.default_max_load_percentage
                ).init(allocator),
                .allocator = allocator,
                .updates = std.atomic.Value(u64).init(0),
                .queries = std.atomic.Value(u64).init(0),
            };
        }
        
        return Self{
            .shards = shards,
            .num_shards = SHARD_COUNT,
            .allocator = allocator,
            .total_strategies = std.atomic.Value(u64).init(0),
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.shards) |*shard| {
            shard.rwlock.lock();
            defer shard.rwlock.unlock();
            
            var iterator = shard.entries.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit(shard.allocator);
            }
            shard.entries.deinit();
        }
        self.allocator.free(self.shards);
    }
    
    fn getShard(self: *Self, hash: info_set.HashType) *StrategyShard {
        const shard_idx = hash & (self.num_shards - 1);
        return &self.shards[shard_idx];
    }
    
    // Update strategy with lock-free approach where possible
    pub fn updateStrategy(
        self: *Self,
        hash: info_set.HashType,
        strategy: []const StrategyValue,
        weight: f32,
    ) !void {
        const shard = self.getShard(hash);
        
        // Try optimistic read first
        shard.rwlock.lockShared();
        const exists = shard.entries.contains(hash);
        shard.rwlock.unlockShared();
        
        if (!exists) {
            // Need write lock to create new entry
            shard.rwlock.lock();
            defer shard.rwlock.unlock();
            
            // Double-check after acquiring write lock
            if (!shard.entries.contains(hash)) {
                const new_entry = try StrategyEntry.init(
                    shard.allocator,
                    hash,
                    @intCast(strategy.len)
                );
                try shard.entries.put(hash, new_entry);
                _ = self.total_strategies.fetchAdd(1, .monotonic);
            }
        }
        
        // Now update the strategy
        shard.rwlock.lock();
        defer shard.rwlock.unlock();
        
        if (shard.entries.getPtr(hash)) |entry| {
            entry.updateSum(strategy, weight);
            _ = shard.updates.fetchAdd(1, .monotonic);
        }
    }
    
    // Get average strategy (read-only operation)
    pub fn getAverageStrategy(
        self: *Self,
        hash: info_set.HashType,
        output: []StrategyValue,
    ) !bool {
        const shard = self.getShard(hash);
        
        shard.rwlock.lockShared();
        defer shard.rwlock.unlockShared();
        
        if (shard.entries.getPtr(hash)) |entry| {
            const avg_strategy = entry.getAverageStrategy();
            @memcpy(output[0..entry.num_actions], avg_strategy);
            _ = shard.queries.fetchAdd(1, .monotonic);
            return true;
        }
        
        return false;
    }
    
    // Batch update for efficiency
    pub fn batchUpdate(
        self: *Self,
        updates: []const StrategyUpdate,
    ) !void {
        // Group updates by shard
        var shard_updates = try self.allocator.alloc(
            std.ArrayList(StrategyUpdate),
            self.num_shards
        );
        defer {
            for (shard_updates) |*list| {
                list.deinit();
            }
            self.allocator.free(shard_updates);
        }
        
        for (shard_updates) |*list| {
            list.* = std.ArrayList(StrategyUpdate).init(self.allocator);
        }
        
        // Sort updates into shards
        for (updates) |update| {
            const shard_idx = update.hash & (self.num_shards - 1);
            try shard_updates[shard_idx].append(update);
        }
        
        // Process each shard's updates
        for (self.shards, 0..) |*shard, i| {
            if (shard_updates[i].items.len == 0) continue;
            
            shard.rwlock.lock();
            defer shard.rwlock.unlock();
            
            for (shard_updates[i].items) |update| {
                if (shard.entries.getPtr(update.hash)) |entry| {
                    entry.updateSum(update.strategy, update.weight);
                } else {
                    // Create new entry
                    var new_entry = try StrategyEntry.init(
                        shard.allocator,
                        update.hash,
                        @intCast(update.strategy.len)
                    );
                    new_entry.updateSum(update.strategy, update.weight);
                    try shard.entries.put(update.hash, new_entry);
                    _ = self.total_strategies.fetchAdd(1, .monotonic);
                }
            }
            
            _ = shard.updates.fetchAdd(shard_updates[i].items.len, .monotonic);
        }
    }
    
    pub const StrategyUpdate = struct {
        hash: info_set.HashType,
        strategy: []const StrategyValue,
        weight: f64,
    };
    
    // Merge strategies from another aggregator (for distributed training)
    pub fn merge(self: *Self, other: *Self) !void {
        for (other.shards, 0..) |*other_shard, shard_idx| {
            other_shard.rwlock.lockShared();
            defer other_shard.rwlock.unlockShared();
            
            const self_shard = &self.shards[shard_idx];
            self_shard.rwlock.lock();
            defer self_shard.rwlock.unlock();
            
            var iterator = other_shard.entries.iterator();
            while (iterator.next()) |other_entry| {
                if (self_shard.entries.getPtr(other_entry.key_ptr.*)) |self_entry| {
                    // Merge strategy sums
                    for (0..self_entry.num_actions) |i| {
                        self_entry.strategy_sum[i] += other_entry.value_ptr.strategy_sum[i];
                    }
                    self_entry.total_weight += other_entry.value_ptr.total_weight;
                    self_entry.iterations += other_entry.value_ptr.iterations;
                } else {
                    // Copy entry
                    const new_entry = try StrategyEntry.init(
                        self_shard.allocator,
                        other_entry.key_ptr.*,
                        other_entry.value_ptr.num_actions
                    );
                    @memcpy(
                        new_entry.strategy_sum,
                        other_entry.value_ptr.strategy_sum[0..other_entry.value_ptr.num_actions]
                    );
                    new_entry.total_weight = other_entry.value_ptr.total_weight;
                    new_entry.iterations = other_entry.value_ptr.iterations;
                    
                    try self_shard.entries.put(other_entry.key_ptr.*, new_entry);
                    _ = self.total_strategies.fetchAdd(1, .monotonic);
                }
            }
        }
    }
    
    // Get statistics
    pub fn getStats(self: *Self) Stats {
        var total_updates: u64 = 0;
        var total_queries: u64 = 0;
        var total_entries: u64 = 0;
        
        for (self.shards) |*shard| {
            total_updates += shard.updates.load(.monotonic);
            total_queries += shard.queries.load(.monotonic);
            
            shard.rwlock.lockShared();
            total_entries += shard.entries.count();
            shard.rwlock.unlockShared();
        }
        
        return .{
            .total_strategies = total_entries,
            .total_updates = total_updates,
            .total_queries = total_queries,
            .average_shard_size = @as(f32, @floatFromInt(total_entries)) / 
                                 @as(f32, @floatFromInt(self.num_shards)),
        };
    }
    
    pub const Stats = struct {
        total_strategies: u64,
        total_updates: u64,
        total_queries: u64,
        average_shard_size: f32,
    };
    
    // Save strategies to file
    pub fn save(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        
        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();
        
        // Write header
        try writer.writeInt(u32, @intCast(self.num_shards), .little);
        const total = self.total_strategies.load(.monotonic);
        try writer.writeInt(u64, total, .little);
        
        // Write strategies from each shard
        for (self.shards) |*shard| {
            shard.rwlock.lockShared();
            defer shard.rwlock.unlockShared();
            
            try writer.writeInt(u32, @intCast(shard.entries.count()), .little);
            
            var iterator = shard.entries.iterator();
            while (iterator.next()) |entry| {
                // Write entry header
                try writer.writeInt(u64, entry.key_ptr.*, .little);
                try writer.writeInt(u8, entry.value_ptr.num_actions, .little);
                try writer.writeAll(std.mem.asBytes(&entry.value_ptr.total_weight));
                try writer.writeInt(u32, entry.value_ptr.iterations, .little);
                
                // Write strategy sum
                for (entry.value_ptr.strategy_sum[0..entry.value_ptr.num_actions]) |sum| {
                    try writer.writeAll(std.mem.asBytes(&sum));
                }
            }
        }
        
        try buffered.flush();
    }
    
    // Load strategies from file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        var buffered = std.io.bufferedReader(file.reader());
        const reader = buffered.reader();
        
        // Read header
        _ = try reader.readInt(u32, .little); // num_shards - not used
        const total_strategies = try reader.readInt(u64, .little);
        
        var aggregator = try Self.init(allocator);
        _ = aggregator.total_strategies.swap(total_strategies, .monotonic);
        
        // Read strategies for each shard
        for (aggregator.shards) |*shard| {
            const entry_count = try reader.readInt(u32, .little);
            
            var i: u32 = 0;
            while (i < entry_count) : (i += 1) {
                // Read entry header
                const hash = try reader.readInt(u64, .little);
                const num_actions = try reader.readInt(u8, .little);
                var total_weight: f64 = undefined;
                _ = try reader.readAll(std.mem.asBytes(&total_weight));
                const iterations = try reader.readInt(u32, .little);
                
                // Create entry
                var entry = try StrategyEntry.init(shard.allocator, hash, num_actions);
                entry.total_weight = total_weight;
                entry.iterations = iterations;
                
                // Read strategy sum
                for (entry.strategy_sum[0..num_actions]) |*sum| {
                    _ = try reader.readAll(std.mem.asBytes(sum));
                }
                
                try shard.entries.put(hash, entry);
            }
        }
        
        return aggregator;
    }
};

// Test strategy entry
test "strategy entry operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var entry = try StrategyEntry.init(allocator, 0x123456789ABCDEF0, 3);
    defer entry.deinit(allocator);
    
    // Test initial uniform strategy
    const initial = entry.getAverageStrategy();
    try testing.expectApproxEqAbs(@as(f32, 1.0/3.0), initial[0], 0.001);
    
    // Update with a strategy
    const strategy = [_]StrategyValue{ 0.5, 0.3, 0.2 };
    entry.updateSum(&strategy, 1.0);
    
    // Check average strategy
    const avg = entry.getAverageStrategy();
    try testing.expectApproxEqAbs(@as(f32, 0.5), avg[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.3), avg[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.2), avg[2], 0.001);
}

// Test strategy aggregator
test "strategy aggregator operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var aggregator = try StrategyAggregator.init(allocator);
    defer aggregator.deinit();
    
    const hash: info_set.HashType = 0x123456789ABCDEF0;
    const strategy = [_]StrategyValue{ 0.6, 0.3, 0.1 };
    
    // Update strategy
    try aggregator.updateStrategy(hash, &strategy, 1.0);
    
    // Get average strategy
    var output: [3]StrategyValue = undefined;
    const found = try aggregator.getAverageStrategy(hash, &output);
    
    try testing.expect(found);
    try testing.expectApproxEqAbs(@as(f32, 0.6), output[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.3), output[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.1), output[2], 0.001);
    
    // Check stats
    const stats = aggregator.getStats();
    try testing.expectEqual(@as(u64, 1), stats.total_strategies);
    try testing.expectEqual(@as(u64, 1), stats.total_updates);
    try testing.expectEqual(@as(u64, 1), stats.total_queries);
}

// Test batch updates
test "batch strategy updates" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var aggregator = try StrategyAggregator.init(allocator);
    defer aggregator.deinit();
    
    const strategy1 = [_]StrategyValue{ 0.5, 0.5 };
    const strategy2 = [_]StrategyValue{ 0.7, 0.3 };
    
    const updates = [_]StrategyAggregator.StrategyUpdate{
        .{ .hash = 0x1111111111111111, .strategy = &strategy1, .weight = 1.0 },
        .{ .hash = 0x2222222222222222, .strategy = &strategy2, .weight = 2.0 },
    };
    
    try aggregator.batchUpdate(&updates);
    
    const stats = aggregator.getStats();
    try testing.expectEqual(@as(u64, 2), stats.total_strategies);
    try testing.expectEqual(@as(u64, 2), stats.total_updates);
}