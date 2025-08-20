// Information Set Hashing and Representation
// Efficient hash-based info set representation for CFR

const std = @import("std");
const game_state = @import("game_state.zig");

// Fast hash functions for poker information sets
pub const HashType = u64;

// Information set representation
pub const InfoSet = struct {
    hash: HashType,
    round: game_state.Round,
    player_id: u8,
    hole_cards: [2]u8,
    board_cards: [5]u8,
    board_size: u8,
    action_sequence: []u8,
    pot_size: u32,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .hash = 0,
            .round = .preflop,
            .player_id = 0,
            .hole_cards = .{ 255, 255 },
            .board_cards = .{ 255, 255, 255, 255, 255 },
            .board_size = 0,
            .action_sequence = try allocator.alloc(u8, 0),
            .pot_size = 0,
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.action_sequence);
    }
    
    // Compute hash for the information set
    pub fn computeHash(self: *Self) HashType {
        var hasher = std.hash.Wyhash.init(0);
        
        // Hash round
        hasher.update(std.mem.asBytes(&self.round));
        
        // Hash player ID
        hasher.update(std.mem.asBytes(&self.player_id));
        
        // Hash hole cards (sorted to ensure consistency)
        var sorted_hole = self.hole_cards;
        if (sorted_hole[0] > sorted_hole[1]) {
            std.mem.swap(u8, &sorted_hole[0], &sorted_hole[1]);
        }
        hasher.update(&sorted_hole);
        
        // Hash board cards (only valid ones)
        if (self.board_size > 0) {
            hasher.update(self.board_cards[0..self.board_size]);
        }
        
        // Hash action sequence
        hasher.update(self.action_sequence);
        
        // Hash pot size (bucketed for abstraction)
        const pot_bucket = bucketPotSize(self.pot_size);
        hasher.update(std.mem.asBytes(&pot_bucket));
        
        self.hash = hasher.final();
        return self.hash;
    }
};

// Compute information set hash directly from game state
pub fn computeInfoSetHash(game: *game_state.GameState, player: u8) !HashType {
    var hasher = std.hash.Wyhash.init(0);
    
    // Hash round
    hasher.update(std.mem.asBytes(&game.round));
    
    // Hash player ID
    hasher.update(std.mem.asBytes(&player));
    
    // Hash player's hole cards (sorted)
    const hand = game.players[player].hand;
    var sorted_cards = hand.cards;
    if (sorted_cards[0] > sorted_cards[1]) {
        std.mem.swap(u8, &sorted_cards[0], &sorted_cards[1]);
    }
    hasher.update(&sorted_cards);
    
    // Hash board cards
    if (game.board_size > 0) {
        hasher.update(game.board[0..game.board_size]);
    }
    
    // Hash abstracted action sequence
    const abstract_sequence = try abstractActionSequence(game);
    defer game.allocator.free(abstract_sequence);
    hasher.update(abstract_sequence);
    
    // Hash pot size bucket
    const pot_bucket = bucketPotSize(game.pot);
    hasher.update(std.mem.asBytes(&pot_bucket));
    
    return hasher.final();
}

// Abstract action sequence for dimensionality reduction
fn abstractActionSequence(game: *game_state.GameState) ![]u8 {
    var abstract = std.ArrayList(u8).init(game.allocator);
    
    // Convert action sequence to abstract representation
    // F = Fold, C = Call/Check, R = Raise (small), B = Big raise, A = All-in
    for (game.action_sequence.items) |action| {
        const abstract_action = switch (action.action_type) {
            .fold => 'F',
            .check => 'C',
            .call => 'C',
            .raise => blk: {
                const raise_ratio = @as(f32, @floatFromInt(action.amount)) / 
                                  @as(f32, @floatFromInt(game.pot));
                if (raise_ratio < 0.33) {
                    break :blk 'R'; // Small raise
                } else if (raise_ratio < 0.75) {
                    break :blk 'B'; // Big raise
                } else {
                    break :blk 'A'; // Near all-in
                }
            },
            .all_in => 'A',
        };
        try abstract.append(abstract_action);
    }
    
    return abstract.toOwnedSlice();
}

// Bucket pot sizes for abstraction
fn bucketPotSize(pot: u32) u8 {
    // Exponential bucketing for pot sizes
    if (pot < 10) return 0;
    if (pot < 25) return 1;
    if (pot < 50) return 2;
    if (pot < 100) return 3;
    if (pot < 200) return 4;
    if (pot < 400) return 5;
    if (pot < 800) return 6;
    if (pot < 1600) return 7;
    if (pot < 3200) return 8;
    return 9;
}

// Information set cache for fast lookup
pub const InfoSetCache = struct {
    cache: std.HashMap(HashType, InfoSetData, std.hash_map.AutoContext(HashType), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    max_size: usize,
    hits: u64,
    misses: u64,
    
    const Self = @This();
    
    pub const InfoSetData = struct {
        strategy: []f32,
        regret: []f32,
        visits: u32,
        last_access: u64,
    };
    
    pub fn init(allocator: std.mem.Allocator, max_size: usize) Self {
        return Self{
            .cache = std.HashMap(HashType, InfoSetData, std.hash_map.AutoContext(HashType), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .max_size = max_size,
            .hits = 0,
            .misses = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.strategy);
            self.allocator.free(entry.value_ptr.regret);
        }
        self.cache.deinit();
    }
    
    pub fn get(self: *Self, hash: HashType) ?*InfoSetData {
        if (self.cache.getPtr(hash)) |data| {
            self.hits += 1;
            data.last_access = @intCast(std.time.milliTimestamp());
            return data;
        }
        self.misses += 1;
        return null;
    }
    
    pub fn put(self: *Self, hash: HashType, data: InfoSetData) !void {
        // Evict old entries if cache is full
        if (self.cache.count() >= self.max_size) {
            try self.evictOldest();
        }
        
        try self.cache.put(hash, data);
    }
    
    fn evictOldest(self: *Self) !void {
        var oldest_hash: ?HashType = null;
        var oldest_time: u64 = std.math.maxInt(u64);
        
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.last_access < oldest_time) {
                oldest_time = entry.value_ptr.last_access;
                oldest_hash = entry.key_ptr.*;
            }
        }
        
        if (oldest_hash) |hash| {
            if (self.cache.fetchRemove(hash)) |entry| {
                self.allocator.free(entry.value.strategy);
                self.allocator.free(entry.value.regret);
            }
        }
    }
    
    pub fn getCacheStats(self: *Self) CacheStats {
        const total = self.hits + self.misses;
        const hit_rate = if (total > 0) 
            @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total))
        else 
            0.0;
            
        return .{
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
            .size = self.cache.count(),
            .max_size = self.max_size,
        };
    }
    
    pub const CacheStats = struct {
        hits: u64,
        misses: u64,
        hit_rate: f32,
        size: usize,
        max_size: usize,
    };
};

// Parallel-safe information set manager
pub const InfoSetManager = struct {
    shards: []InfoSetShard,
    num_shards: usize,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    const SHARD_COUNT = 16; // Power of 2 for fast modulo
    
    pub const InfoSetShard = struct {
        mutex: std.Thread.Mutex,
        cache: InfoSetCache,
    };
    
    pub fn init(allocator: std.mem.Allocator, cache_size_per_shard: usize) !Self {
        const shards = try allocator.alloc(InfoSetShard, SHARD_COUNT);
        
        for (shards) |*shard| {
            shard.* = .{
                .mutex = std.Thread.Mutex{},
                .cache = InfoSetCache.init(allocator, cache_size_per_shard),
            };
        }
        
        return Self{
            .shards = shards,
            .num_shards = SHARD_COUNT,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.shards) |*shard| {
            shard.cache.deinit();
        }
        self.allocator.free(self.shards);
    }
    
    pub fn getShard(self: *Self, hash: HashType) *InfoSetShard {
        const shard_idx = hash & (self.num_shards - 1);
        return &self.shards[shard_idx];
    }
    
    pub fn get(self: *Self, hash: HashType) ?InfoSetCache.InfoSetData {
        const shard = self.getShard(hash);
        shard.mutex.lock();
        defer shard.mutex.unlock();
        
        if (shard.cache.get(hash)) |data| {
            return data.*;
        }
        return null;
    }
    
    pub fn put(self: *Self, hash: HashType, data: InfoSetCache.InfoSetData) !void {
        const shard = self.getShard(hash);
        shard.mutex.lock();
        defer shard.mutex.unlock();
        
        try shard.cache.put(hash, data);
    }
};

// Test information set hashing
test "info set hash computation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var game = try game_state.GameState.init(allocator, 2, 5, 10);
    defer game.deinit();
    
    // Set up a simple game state
    game.players[0].hand = game_state.Hand.init(0, 1); // AA
    game.players[1].hand = game_state.Hand.init(12, 25); // KK
    
    const hash1 = try computeInfoSetHash(&game, 0);
    const hash2 = try computeInfoSetHash(&game, 1);
    
    // Different players should have different hashes
    try testing.expect(hash1 != hash2);
    
    // Same state should produce same hash
    const hash1_again = try computeInfoSetHash(&game, 0);
    try testing.expectEqual(hash1, hash1_again);
}

// Test information set cache
test "info set cache operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var cache = InfoSetCache.init(allocator, 100);
    defer cache.deinit();
    
    const hash: HashType = 0x123456789ABCDEF0;
    
    // Test miss
    try testing.expect(cache.get(hash) == null);
    try testing.expectEqual(@as(u64, 1), cache.misses);
    
    // Test put and hit
    const data = InfoSetCache.InfoSetData{
        .strategy = try allocator.alloc(f32, 3),
        .regret = try allocator.alloc(f32, 3),
        .visits = 1,
        .last_access = 0,
    };
    defer allocator.free(data.strategy);
    defer allocator.free(data.regret);
    
    try cache.put(hash, data);
    
    const retrieved = cache.get(hash);
    try testing.expect(retrieved != null);
    try testing.expectEqual(@as(u64, 1), cache.hits);
    try testing.expectEqual(@as(u32, 1), retrieved.?.visits);
}

// Test bucket pot size
test "pot size bucketing" {
    const testing = std.testing;
    
    try testing.expectEqual(@as(u8, 0), bucketPotSize(5));
    try testing.expectEqual(@as(u8, 1), bucketPotSize(15));
    try testing.expectEqual(@as(u8, 2), bucketPotSize(35));
    try testing.expectEqual(@as(u8, 3), bucketPotSize(75));
    try testing.expectEqual(@as(u8, 9), bucketPotSize(10000));
}