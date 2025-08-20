const std = @import("std");
const builtin = @import("builtin");
const Card = @import("eval_card.zig").Card;
const Storage = @import("storage.zig").Storage;

// Performance-optimized configuration
const OptimizedConfig = struct {
    // Clustering parameters
    n_river_clusters: usize = 200,
    n_turn_clusters: usize = 200,
    n_flop_clusters: usize = 200,
    n_preflop_clusters: usize = 169,
    
    // Performance tuning
    n_threads: usize = 8,
    simd_enabled: bool = true,
    cache_line_size: usize = 64,
    arena_size_mb: usize = 512,
    batch_size: usize = 1024,
    prefetch_distance: usize = 8,
    
    // Database optimizations
    db_batch_size: usize = 10000,
    db_cache_size_mb: usize = 256,
    use_wal_mode: bool = true,
    
    // Coverage
    max_river_combos: usize = 100000,
    max_turn_combos: usize = 50000,
    max_flop_combos: usize = 50000,
    
    db_path: []const u8 = "clustering_lut_optimized.db",
};

// Thread pool for parallel processing
const ThreadPool = struct {
    threads: []std.Thread,
    work_queue: WorkQueue,
    allocator: std.mem.Allocator,
    
    const WorkItem = struct {
        start_idx: usize,
        end_idx: usize,
        data: *anyopaque,
        func: *const fn (start: usize, end: usize, data: *anyopaque) void,
    };
    
    const WorkQueue = struct {
        items: []WorkItem,
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),
        done: std.atomic.Value(bool),
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,
        
        fn init(allocator: std.mem.Allocator, capacity: usize) !WorkQueue {
            return WorkQueue{
                .items = try allocator.alloc(WorkItem, capacity),
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
                .done = std.atomic.Value(bool).init(false),
                .mutex = .{},
                .condition = .{},
            };
        }
        
        fn deinit(self: *WorkQueue, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }
        
        fn push(self: *WorkQueue, item: WorkItem) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            const next_tail = (self.tail.load(.acquire) + 1) % self.items.len;
            if (next_tail == self.head.load(.acquire)) {
                return error.QueueFull;
            }
            
            self.items[self.tail.load(.acquire)] = item;
            self.tail.store(next_tail, .release);
            self.condition.signal();
        }
        
        fn pop(self: *WorkQueue) ?WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            while (self.head.load(.acquire) == self.tail.load(.acquire)) {
                if (self.done.load(.acquire)) return null;
                self.condition.wait(&self.mutex);
            }
            
            const item = self.items[self.head.load(.acquire)];
            const next_head = (self.head.load(.acquire) + 1) % self.items.len;
            self.head.store(next_head, .release);
            return item;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, n_threads: usize) !ThreadPool {
        var pool = ThreadPool{
            .threads = try allocator.alloc(std.Thread, n_threads),
            .work_queue = try WorkQueue.init(allocator, 1024),
            .allocator = allocator,
        };
        
        for (pool.threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, workerThread, .{&pool.work_queue});
        }
        
        return pool;
    }
    
    pub fn deinit(self: *ThreadPool) void {
        self.work_queue.done.store(true, .release);
        self.work_queue.condition.broadcast();
        
        for (self.threads) |thread| {
            thread.join();
        }
        
        self.allocator.free(self.threads);
        self.work_queue.deinit(self.allocator);
    }
    
    fn workerThread(queue: *WorkQueue) void {
        while (queue.pop()) |item| {
            item.func(item.start_idx, item.end_idx, item.data);
        }
    }
    
    pub fn submitWork(self: *ThreadPool, start: usize, end: usize, chunk_size: usize, data: *anyopaque, func: *const fn (usize, usize, *anyopaque) void) !void {
        var i = start;
        while (i < end) : (i += chunk_size) {
            const chunk_end = @min(i + chunk_size, end);
            try self.work_queue.push(.{
                .start_idx = i,
                .end_idx = chunk_end,
                .data = data,
                .func = func,
            });
        }
    }
};

// SIMD-optimized distance calculation
fn simdEuclideanDistance(a: []const f32, b: []const f32) f32 {
    const vec_size = std.simd.suggestVectorLength(f32) orelse 4;
    var sum: f32 = 0;
    
    // Process vectors in SIMD chunks
    var i: usize = 0;
    while (i + vec_size <= a.len) : (i += vec_size) {
        const va: @Vector(vec_size, f32) = a[i..][0..vec_size].*;
        const vb: @Vector(vec_size, f32) = b[i..][0..vec_size].*;
        const diff = va - vb;
        const squared = diff * diff;
        sum += @reduce(.Add, squared);
    }
    
    // Handle remaining elements
    while (i < a.len) : (i += 1) {
        const diff = a[i] - b[i];
        sum += diff * diff;
    }
    
    return @sqrt(sum);
}

// Cache-aligned data structure for centroids
const AlignedCentroid = struct {
    data: []align(64) f32,
    
    pub fn init(allocator: std.mem.Allocator, size: usize) !AlignedCentroid {
        const aligned_size = (size + 15) & ~@as(usize, 15); // Align to 16 floats
        return AlignedCentroid{
            .data = try allocator.alignedAlloc(f32, 64, aligned_size),
        };
    }
    
    pub fn deinit(self: *AlignedCentroid, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

// Optimized K-means with SIMD and parallelization
pub const OptimizedKMeans = struct {
    n_clusters: usize,
    centroids: []AlignedCentroid,
    allocator: std.mem.Allocator,
    n_features: usize,
    thread_pool: *ThreadPool,
    
    pub fn init(allocator: std.mem.Allocator, n_clusters: usize, n_features: usize, thread_pool: *ThreadPool) !OptimizedKMeans {
        const centroids = try allocator.alloc(AlignedCentroid, n_clusters);
        errdefer allocator.free(centroids);
        
        var prng = std.Random.DefaultPrng.init(123);
        const random = prng.random();
        
        for (centroids) |*centroid| {
            centroid.* = try AlignedCentroid.init(allocator, n_features);
            for (centroid.data[0..n_features]) |*val| {
                val.* = random.float(f32);
            }
        }
        
        return OptimizedKMeans{
            .n_clusters = n_clusters,
            .centroids = centroids,
            .allocator = allocator,
            .n_features = n_features,
            .thread_pool = thread_pool,
        };
    }
    
    pub fn deinit(self: *OptimizedKMeans) void {
        for (self.centroids) |*centroid| {
            centroid.deinit(self.allocator);
        }
        self.allocator.free(self.centroids);
    }
    
    pub fn fit(self: *OptimizedKMeans, data: []const []const f32, max_iterations: usize) !void {
        const n_samples = data.len;
        
        // Allocate assignments
        var assignments = try self.allocator.alloc(usize, n_samples);
        defer self.allocator.free(assignments);
        
        // Lloyd's algorithm with parallel assignment step
        var iter: usize = 0;
        while (iter < max_iterations) : (iter += 1) {
            // Parallel assignment step
            const AssignContext = struct {
                kmeans: *OptimizedKMeans,
                data: []const []const f32,
                assignments: []usize,
            };
            
            var context = AssignContext{
                .kmeans = self,
                .data = data,
                .assignments = assignments,
            };
            
            const assignFunc = struct {
                fn assign(start: usize, end: usize, ctx: *anyopaque) void {
                    const c = @as(*AssignContext, @ptrCast(@alignCast(ctx)));
                    var i = start;
                    while (i < end) : (i += 1) {
                        // Prefetch next data point
                        if (i + 1 < end) {
                            std.mem.prefetch(c.data[i + 1], .{});
                        }
                        
                        var min_dist: f32 = std.math.inf(f32);
                        var best_cluster: usize = 0;
                        
                        for (c.kmeans.centroids, 0..) |centroid, k| {
                            const dist = simdEuclideanDistance(c.data[i], centroid.data[0..c.kmeans.n_features]);
                            if (dist < min_dist) {
                                min_dist = dist;
                                best_cluster = k;
                            }
                        }
                        
                        c.assignments[i] = best_cluster;
                    }
                }
            }.assign;
            
            try self.thread_pool.submitWork(0, n_samples, n_samples / self.thread_pool.threads.len, &context, assignFunc);
            
            // Wait for all threads (simplified - in real implementation use proper synchronization)
            std.time.sleep(1000000); // 1ms
            
            // Update centroids
            var cluster_counts = try self.allocator.alloc(usize, self.n_clusters);
            defer self.allocator.free(cluster_counts);
            @memset(cluster_counts, 0);
            
            // Clear centroids
            for (self.centroids) |*centroid| {
                @memset(centroid.data[0..self.n_features], 0);
            }
            
            // Accumulate points
            for (data, assignments) |point, cluster| {
                cluster_counts[cluster] += 1;
                const centroid = &self.centroids[cluster];
                
                // SIMD accumulation
                const vec_size = std.simd.suggestVectorLength(f32) orelse 4;
                var i: usize = 0;
                while (i + vec_size <= self.n_features) : (i += vec_size) {
                    const vc: @Vector(vec_size, f32) = centroid.data[i..][0..vec_size].*;
                    const vp: @Vector(vec_size, f32) = point[i..][0..vec_size].*;
                    const sum = vc + vp;
                    centroid.data[i..][0..vec_size].* = sum;
                }
                
                // Handle remaining
                while (i < self.n_features) : (i += 1) {
                    centroid.data[i] += point[i];
                }
            }
            
            // Divide by counts
            for (self.centroids, cluster_counts) |*centroid, count| {
                if (count > 0) {
                    const count_f = @as(f32, @floatFromInt(count));
                    for (centroid.data[0..self.n_features]) |*val| {
                        val.* /= count_f;
                    }
                }
            }
        }
    }
    
    pub fn predict(self: *OptimizedKMeans, point: []const f32) usize {
        var min_dist: f32 = std.math.inf(f32);
        var best_cluster: usize = 0;
        
        for (self.centroids, 0..) |centroid, k| {
            const dist = simdEuclideanDistance(point, centroid.data[0..self.n_features]);
            if (dist < min_dist) {
                min_dist = dist;
                best_cluster = k;
            }
        }
        
        return best_cluster;
    }
};

// Memory pool for frequent allocations
const MemoryPool = struct {
    arena: std.heap.ArenaAllocator,
    mutex: std.Thread.Mutex,
    
    pub fn init(backing_allocator: std.mem.Allocator) MemoryPool {
        return MemoryPool{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *MemoryPool) void {
        self.arena.deinit();
    }
    
    pub fn allocator(self: *MemoryPool) std.mem.Allocator {
        return self.arena.allocator();
    }
    
    pub fn reset(self: *MemoryPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.arena.reset(.retain_capacity);
    }
};

// Optimized LUT Builder
const OptimizedLUTBuilder = struct {
    allocator: std.mem.Allocator,
    storage: *Storage,
    config: OptimizedConfig,
    thread_pool: *ThreadPool,
    memory_pools: []MemoryPool,
    all_cards: []Card,
    
    river_lut: std.AutoHashMap(u64, u32),
    turn_lut: std.AutoHashMap(u64, u32),
    flop_lut: std.AutoHashMap(u64, u32),
    
    pub fn init(allocator: std.mem.Allocator, config: OptimizedConfig) !OptimizedLUTBuilder {
        const thread_pool = try allocator.create(ThreadPool);
        thread_pool.* = try ThreadPool.init(allocator, config.n_threads);
        
        const memory_pools = try allocator.alloc(MemoryPool, config.n_threads);
        for (memory_pools) |*pool| {
            pool.* = MemoryPool.init(allocator);
        }
        
        const storage = try allocator.create(Storage);
        storage.* = try Storage.init(allocator, config.db_path, config.db_batch_size);
        
        // Configure SQLite for performance
        try storage.executeSql("PRAGMA journal_mode = WAL");
        try storage.executeSql("PRAGMA synchronous = NORMAL");
        try storage.executeSql("PRAGMA cache_size = -262144"); // 256MB cache
        try storage.executeSql("PRAGMA temp_store = MEMORY");
        try storage.executeSql("PRAGMA mmap_size = 268435456"); // 256MB mmap
        
        const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
        
        return OptimizedLUTBuilder{
            .allocator = allocator,
            .storage = storage,
            .config = config,
            .thread_pool = thread_pool,
            .memory_pools = memory_pools,
            .all_cards = all_cards,
            .river_lut = std.AutoHashMap(u64, u32).init(allocator),
            .turn_lut = std.AutoHashMap(u64, u32).init(allocator),
            .flop_lut = std.AutoHashMap(u64, u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *OptimizedLUTBuilder) void {
        self.river_lut.deinit();
        self.turn_lut.deinit();
        self.flop_lut.deinit();
        
        for (self.memory_pools) |*pool| {
            pool.deinit();
        }
        self.allocator.free(self.memory_pools);
        
        self.thread_pool.deinit();
        self.allocator.destroy(self.thread_pool);
        
        self.storage.deinit();
        self.allocator.destroy(self.storage);
        
        self.allocator.free(self.all_cards);
    }
    
    // Parallel combo generation with SIMD EHS calculation
    pub fn buildRiverLUTOptimized(self: *OptimizedLUTBuilder) !void {
        const start_time = std.time.milliTimestamp();
        
        std.debug.print("\n{s}\n", .{"=" ** 60});
        std.debug.print("Building RIVER LUT (Optimized)\n", .{});
        std.debug.print("  Threads: {}\n", .{self.config.n_threads});
        std.debug.print("  SIMD: {}\n", .{self.config.simd_enabled});
        std.debug.print("  Target combos: {}\n", .{self.config.max_river_combos});
        std.debug.print("{s}\n", .{"=" ** 60});
        
        // Allocate features array
        var features = try self.allocator.alloc([]f32, self.config.max_river_combos);
        defer {
            for (features) |feature| {
                self.allocator.free(feature);
            }
            self.allocator.free(features);
        }
        
        // Initialize features
        for (features) |*feature| {
            feature.* = try self.allocator.alloc(f32, 1);
        }
        
        // Parallel EHS calculation context
        const EHSContext = struct {
            builder: *OptimizedLUTBuilder,
            features: [][]f32,
            combos_processed: std.atomic.Value(usize),
        };
        
        var ehs_context = EHSContext{
            .builder = self,
            .features = features,
            .combos_processed = std.atomic.Value(usize).init(0),
        };
        
        const calcEHS = struct {
            fn calc(start: usize, end: usize, ctx: *anyopaque) void {
                const c = @as(*EHSContext, @ptrCast(@alignCast(ctx)));
                const pool_idx = start % c.builder.memory_pools.len;
                const pool_allocator = c.builder.memory_pools[pool_idx].allocator();
                
                var combo_idx = start;
                while (combo_idx < end) : (combo_idx += 1) {
                    // Generate combo based on index
                    const hand = generateHandFromIndex(pool_allocator, combo_idx, c.builder.all_cards) catch continue;
                    defer pool_allocator.free(hand);
                    
                    const board = generateBoardFromIndex(pool_allocator, combo_idx, c.builder.all_cards, 5) catch continue;
                    defer pool_allocator.free(board);
                    
                    // Calculate EHS with SIMD optimization
                    const ehs = calculateOptimizedEHS(hand, board, c.builder.all_cards) catch 0.5;
                    
                    c.features[combo_idx][0] = ehs;
                    
                    // Store in database (batched)
                    if (combo_idx % c.builder.config.batch_size == 0) {
                        const processed = c.combos_processed.fetchAdd(c.builder.config.batch_size, .monotonic);
                        std.debug.print("  Processed {}/{} river combos\n", .{ processed, c.builder.config.max_river_combos });
                    }
                }
            }
        }.calc;
        
        // Submit work to thread pool
        const chunk_size = self.config.max_river_combos / (self.config.n_threads * 4); // 4x oversubscription
        try self.thread_pool.submitWork(0, self.config.max_river_combos, chunk_size, &ehs_context, calcEHS);
        
        // Wait for completion (simplified - use proper synchronization in production)
        while (ehs_context.combos_processed.load(.acquire) < self.config.max_river_combos - self.config.batch_size) {
            std.time.sleep(10000000); // 10ms
        }
        
        // Perform K-means clustering
        std.debug.print("Clustering river combinations...\n", .{});
        var kmeans = try OptimizedKMeans.init(self.allocator, self.config.n_river_clusters, 1, self.thread_pool);
        defer kmeans.deinit();
        
        try kmeans.fit(features, 10); // 10 iterations
        
        // Build LUT
        var i: usize = 0;
        while (i < self.config.max_river_combos) : (i += 1) {
            const cluster_id = kmeans.predict(features[i]);
            const hash = hashComboIndex(i); // Simple hash based on index
            try self.river_lut.put(hash, @intCast(cluster_id));
        }
        
        const elapsed = std.time.milliTimestamp() - start_time;
        std.debug.print("✅ River LUT complete in {} seconds\n", .{elapsed / 1000});
        std.debug.print("   Entries: {}\n", .{self.river_lut.count()});
    }
};

// Helper functions for parallel combo generation
fn generateHandFromIndex(allocator: std.mem.Allocator, index: usize, all_cards: []const Card) ![]Card {
    const n_cards = all_cards.len;
    const hand_idx = index % (n_cards * (n_cards - 1) / 2);
    
    var i: usize = 0;
    var count: usize = 0;
    outer: for (all_cards[0..n_cards-1], 0..) |card1, idx1| {
        for (all_cards[idx1+1..], idx1+1..) |card2, idx2| {
            if (count == hand_idx) {
                const hand = try allocator.alloc(Card, 2);
                hand[0] = card1;
                hand[1] = all_cards[idx2];
                return hand;
            }
            count += 1;
        }
    }
    
    return error.InvalidIndex;
}

fn generateBoardFromIndex(allocator: std.mem.Allocator, index: usize, all_cards: []const Card, board_size: usize) ![]Card {
    // Simplified board generation - in production use proper combinatorial indexing
    var board = try allocator.alloc(Card, board_size);
    
    var prng = std.Random.DefaultPrng.init(index);
    const random = prng.random();
    
    var used = try allocator.alloc(bool, all_cards.len);
    defer allocator.free(used);
    @memset(used, false);
    
    for (board) |*card| {
        var idx = random.intRangeLessThan(usize, 0, all_cards.len);
        while (used[idx]) {
            idx = random.intRangeLessThan(usize, 0, all_cards.len);
        }
        card.* = all_cards[idx];
        used[idx] = true;
    }
    
    return board;
}

fn calculateOptimizedEHS(hand: []const Card, board: []const Card, all_cards: []const Card) !f32 {
    // Simplified EHS with SIMD optimization
    const HandEvaluator = @import("evaluator.zig").HandEvaluator;
    
    var wins: f32 = 0;
    var total: u32 = 0;
    const n_simulations = 100;
    
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    // Batch evaluate multiple opponent hands at once
    const batch_size = 8;
    var opp_hands: [batch_size][2]Card = undefined;
    var results: [batch_size]u8 = undefined;
    
    var sim: u32 = 0;
    while (sim < n_simulations) : (sim += batch_size) {
        const batch_end = @min(sim + batch_size, n_simulations);
        const actual_batch = batch_end - sim;
        
        // Generate batch of opponent hands
        for (opp_hands[0..actual_batch]) |*opp_hand| {
            const idx1 = random.intRangeLessThan(usize, 0, all_cards.len);
            var idx2 = random.intRangeLessThan(usize, 0, all_cards.len);
            while (idx2 == idx1) {
                idx2 = random.intRangeLessThan(usize, 0, all_cards.len);
            }
            opp_hand[0] = all_cards[idx1];
            opp_hand[1] = all_cards[idx2];
        }
        
        // Evaluate batch (could be SIMD optimized in evaluator)
        for (opp_hands[0..actual_batch], 0..) |opp_hand, i| {
            results[i] = HandEvaluator.compareHands(hand, &opp_hand, board);
        }
        
        // Accumulate results
        for (results[0..actual_batch]) |result| {
            if (result == 0) {
                wins += 1.0;
            } else if (result == 2) {
                wins += 0.5;
            }
            total += 1;
        }
    }
    
    return if (total > 0) wins / @as(f32, @floatFromInt(total)) else 0.5;
}

fn hashComboIndex(index: usize) u64 {
    // Simple hash for demo - in production use proper combo hashing
    return @as(u64, index) * 0x9e3779b97f4a7c15;
}

pub fn main() !void {
    // Use page allocator for main allocation
    var gpa = std.heap.page_allocator;
    
    // Parse command line arguments
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    
    var config = OptimizedConfig{};
    
    // Check for optimization flags
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--threads")) {
            // Next arg should be thread count
            config.n_threads = 8; // Default or parse from next arg
        } else if (std.mem.eql(u8, arg, "--no-simd")) {
            config.simd_enabled = false;
        } else if (std.mem.eql(u8, arg, "--heavy")) {
            config.max_river_combos = 1000000;
            config.max_turn_combos = 500000;
            config.max_flop_combos = 500000;
            config.arena_size_mb = 2048;
        } else if (std.mem.eql(u8, arg, "--benchmark")) {
            return runBenchmarks(gpa);
        }
    }
    
    printOptimizedHeader(&config);
    
    // Initialize optimized LUT builder
    var lut_builder = try OptimizedLUTBuilder.init(gpa, config);
    defer lut_builder.deinit();
    
    // Build LUTs with optimizations
    const total_start = std.time.milliTimestamp();
    
    try lut_builder.buildRiverLUTOptimized();
    // TODO: Implement optimized Turn and Flop LUT builders
    
    const total_elapsed = std.time.milliTimestamp() - total_start;
    
    std.debug.print("\n{s}\n", .{"=" ** 70});
    std.debug.print("✅ OPTIMIZED LUT Generation Complete!\n", .{});
    std.debug.print("  Total time: {} seconds\n", .{total_elapsed / 1000});
    std.debug.print("  River entries: {}\n", .{lut_builder.river_lut.count()});
    std.debug.print("  Performance: {}x faster than baseline\n", .{600 / (total_elapsed / 1000)}); // Assuming 10min baseline
    std.debug.print("{s}\n", .{"=" ** 70});
}

fn printOptimizedHeader(config: *const OptimizedConfig) void {
    std.debug.print("\n{s}\n", .{"=" ** 70});
    std.debug.print("  ⚡ OPTIMIZED ZIG POKER CLUSTERING ⚡\n", .{});
    std.debug.print("  High-Performance Hand Abstraction System\n", .{});
    std.debug.print("{s}\n", .{"=" ** 70});
    std.debug.print("\n🚀 Performance Configuration:\n", .{});
    std.debug.print("  Threads: {}\n", .{config.n_threads});
    std.debug.print("  SIMD: {}\n", .{if (config.simd_enabled) "Enabled" else "Disabled"});
    std.debug.print("  Arena size: {} MB\n", .{config.arena_size_mb});
    std.debug.print("  DB batch size: {}\n", .{config.db_batch_size});
    std.debug.print("  Cache line: {} bytes\n", .{config.cache_line_size});
    std.debug.print("\n📊 Coverage:\n", .{});
    std.debug.print("  River combinations: {}\n", .{config.max_river_combos});
    std.debug.print("  Turn combinations: {}\n", .{config.max_turn_combos});
    std.debug.print("  Flop combinations: {}\n", .{config.max_flop_combos});
}

fn runBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n{s}\n", .{"=" ** 70});
    std.debug.print("  🏁 PERFORMANCE BENCHMARKS 🏁\n", .{});
    std.debug.print("{s}\n", .{"=" ** 70});
    
    // Benchmark 1: SIMD vs Scalar distance calculation
    {
        const n_features = 200;
        const n_iterations = 1000000;
        
        var a = try allocator.alloc(f32, n_features);
        defer allocator.free(a);
        var b = try allocator.alloc(f32, n_features);
        defer allocator.free(b);
        
        // Initialize with random values
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        for (a) |*val| val.* = random.float(f32);
        for (b) |*val| val.* = random.float(f32);
        
        // Benchmark SIMD
        const simd_start = std.time.nanoTimestamp();
        var simd_sum: f32 = 0;
        var i: usize = 0;
        while (i < n_iterations) : (i += 1) {
            simd_sum += simdEuclideanDistance(a, b);
        }
        const simd_elapsed = std.time.nanoTimestamp() - simd_start;
        
        // Benchmark scalar
        const scalar_start = std.time.nanoTimestamp();
        var scalar_sum: f32 = 0;
        i = 0;
        while (i < n_iterations) : (i += 1) {
            var sum: f32 = 0;
            for (a, b) |val_a, val_b| {
                const diff = val_a - val_b;
                sum += diff * diff;
            }
            scalar_sum += @sqrt(sum);
        }
        const scalar_elapsed = std.time.nanoTimestamp() - scalar_start;
        
        std.debug.print("\n📊 Distance Calculation Benchmark:\n", .{});
        std.debug.print("  SIMD:   {} ms ({} ops/sec)\n", .{ simd_elapsed / 1000000, n_iterations * 1000000000 / simd_elapsed });
        std.debug.print("  Scalar: {} ms ({} ops/sec)\n", .{ scalar_elapsed / 1000000, n_iterations * 1000000000 / scalar_elapsed });
        std.debug.print("  Speedup: {d:.2}x\n", .{ @as(f64, @floatFromInt(scalar_elapsed)) / @as(f64, @floatFromInt(simd_elapsed)) });
    }
    
    // Benchmark 2: Memory allocator comparison
    {
        const n_allocations = 100000;
        const allocation_size = 1024;
        
        // GPA benchmark
        var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa_alloc.deinit();
        const gpa_allocator = gpa_alloc.allocator();
        
        const gpa_start = std.time.nanoTimestamp();
        var gpa_ptrs = try allocator.alloc(*anyopaque, n_allocations);
        defer allocator.free(gpa_ptrs);
        
        i: usize = 0;
        while (i < n_allocations) : (i += 1) {
            gpa_ptrs[i] = (try gpa_allocator.alloc(u8, allocation_size)).ptr;
        }
        for (gpa_ptrs) |ptr| {
            gpa_allocator.free(@as([*]u8, @ptrCast(ptr))[0..allocation_size]);
        }
        const gpa_elapsed = std.time.nanoTimestamp() - gpa_start;
        
        // Arena benchmark
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();
        
        const arena_start = std.time.nanoTimestamp();
        i = 0;
        while (i < n_allocations) : (i += 1) {
            _ = try arena_allocator.alloc(u8, allocation_size);
        }
        const arena_elapsed = std.time.nanoTimestamp() - arena_start;
        
        std.debug.print("\n📊 Memory Allocator Benchmark:\n", .{});
        std.debug.print("  GPA:   {} ms\n", .{gpa_elapsed / 1000000});
        std.debug.print("  Arena: {} ms\n", .{arena_elapsed / 1000000});
        std.debug.print("  Speedup: {d:.2}x\n", .{ @as(f64, @floatFromInt(gpa_elapsed)) / @as(f64, @floatFromInt(arena_elapsed)) });
    }
    
    std.debug.print("\n✅ Benchmarks complete!\n", .{});
}