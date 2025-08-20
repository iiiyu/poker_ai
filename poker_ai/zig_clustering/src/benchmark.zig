const std = @import("std");
const builtin = @import("builtin");

// Import both original and optimized versions
const OriginalEquity = @import("equity_calculator.zig");
const OptimizedEquity = @import("optimized_equity.zig");
const OptimizedStorage = @import("optimized_storage.zig");
const Card = @import("eval_card.zig").Card;

const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_time_ns: i128,
    avg_time_ns: i128,
    ops_per_sec: f64,
    speedup: f64,
    memory_used: usize,
};

const BenchmarkSuite = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),
    baseline_times: std.StringHashMap(i128),
    
    pub fn init(allocator: std.mem.Allocator) BenchmarkSuite {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
            .baseline_times = std.StringHashMap(i128).init(allocator),
        };
    }
    
    pub fn deinit(self: *BenchmarkSuite) void {
        self.results.deinit();
        self.baseline_times.deinit();
    }
    
    pub fn runBenchmark(
        self: *BenchmarkSuite,
        name: []const u8,
        iterations: usize,
        comptime func: fn (*std.mem.Allocator, usize) anyerror!void,
        is_baseline: bool,
    ) !void {
        // Warm-up run
        try func(&self.allocator, 1);
        
        // Measure memory before
        const mem_before = if (builtin.os.tag == .linux) blk: {
            const info = try std.process.getCurMemory();
            break :blk info.rss;
        } else 0;
        
        // Run benchmark
        const start_time = std.time.nanoTimestamp();
        try func(&self.allocator, iterations);
        const end_time = std.time.nanoTimestamp();
        
        // Measure memory after
        const mem_after = if (builtin.os.tag == .linux) blk: {
            const info = try std.process.getCurMemory();
            break :blk info.rss;
        } else 0;
        
        const total_time = end_time - start_time;
        const avg_time = @divFloor(total_time, @as(i128, @intCast(iterations)));
        const ops_per_sec = if (total_time > 0) 
            @as(f64, @floatFromInt(iterations)) * 1_000_000_000.0 / @as(f64, @floatFromInt(total_time))
        else 0;
        
        // Calculate speedup
        const speedup = if (is_baseline) blk: {
            try self.baseline_times.put(name, total_time);
            break :blk 1.0;
        } else blk: {
            if (self.baseline_times.get(name)) |baseline_time| {
                break :blk @as(f64, @floatFromInt(baseline_time)) / @as(f64, @floatFromInt(total_time));
            }
            break :blk 0.0;
        };
        
        try self.results.append(.{
            .name = name,
            .iterations = iterations,
            .total_time_ns = total_time,
            .avg_time_ns = avg_time,
            .ops_per_sec = ops_per_sec,
            .speedup = speedup,
            .memory_used = mem_after -% mem_before,
        });
    }
    
    pub fn printResults(self: *BenchmarkSuite) void {
        std.debug.print("\n{s}\n", .{"=" ** 80});
        std.debug.print("BENCHMARK RESULTS\n", .{});
        std.debug.print("{s}\n", .{"=" ** 80});
        std.debug.print("{s:<40} {s:>10} {s:>12} {s:>12} {s:>10}\n", .{
            "Benchmark", "Iterations", "Time (ms)", "Ops/sec", "Speedup",
        });
        std.debug.print("{s}\n", .{"-" ** 80});
        
        for (self.results.items) |result| {
            const time_ms = @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0;
            std.debug.print("{s:<40} {d:>10} {d:>12.2} {d:>12.0} {d:>10.2}x\n", .{
                result.name,
                result.iterations,
                time_ms,
                result.ops_per_sec,
                result.speedup,
            });
        }
        
        std.debug.print("{s}\n", .{"=" ** 80});
    }
};

// Benchmark functions
fn benchmarkOriginalEHS(allocator: *std.mem.Allocator, iterations: usize) !void {
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator.*);
    defer allocator.free(all_cards);
    
    var calc = OriginalEquity.EquityCalculator.init(allocator.*);
    
    const hand = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "hearts"),
    };
    
    const board = [_]Card{
        Card.init(2, "spades"),
        Card.init(3, "hearts"),
        Card.init(5, "diamonds"),
        Card.init(7, "clubs"),
        Card.init(9, "spades"),
    };
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try calc.calculateEHS(&hand, &board, all_cards, 100, 42 + i);
    }
}

fn benchmarkOptimizedEHS(allocator: *std.mem.Allocator, iterations: usize) !void {
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator.*);
    defer allocator.free(all_cards);
    
    var calc = try OptimizedEquity.OptimizedEquityCalculator.init(allocator.*, 32, 1);
    defer calc.deinit();
    
    const hand = [_]Card{
        Card.init(14, "spades"),
        Card.init(14, "hearts"),
    };
    
    const board = [_]Card{
        Card.init(2, "spades"),
        Card.init(3, "hearts"),
        Card.init(5, "diamonds"),
        Card.init(7, "clubs"),
        Card.init(9, "spades"),
    };
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try calc.calculateEHSOptimized(&hand, &board, all_cards, 100, 0);
    }
}

fn benchmarkParallelEHS(allocator: *std.mem.Allocator, iterations: usize) !void {
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator.*);
    defer allocator.free(all_cards);
    
    var calc = try OptimizedEquity.ParallelEHSCalculator.init(allocator.*, 8, 32);
    defer calc.deinit();
    
    // Create batch of hands and boards
    const batch_size = 100;
    var hands = try allocator.alloc([]Card, batch_size);
    defer {
        for (hands) |hand| allocator.free(hand);
        allocator.free(hands);
    }
    
    var boards = try allocator.alloc([]Card, batch_size);
    defer {
        for (boards) |board| allocator.free(board);
        allocator.free(boards);
    }
    
    // Initialize with test data
    for (hands, boards) |*hand, *board| {
        hand.* = try allocator.alloc(Card, 2);
        hand.*[0] = Card.init(14, "spades");
        hand.*[1] = Card.init(14, "hearts");
        
        board.* = try allocator.alloc(Card, 5);
        board.*[0] = Card.init(2, "spades");
        board.*[1] = Card.init(3, "hearts");
        board.*[2] = Card.init(5, "diamonds");
        board.*[3] = Card.init(7, "clubs");
        board.*[4] = Card.init(9, "spades");
    }
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const results = try calc.processBatch(hands, boards, all_cards, 100);
        allocator.free(results);
    }
}

fn benchmarkMemoryAllocators(allocator: *std.mem.Allocator, iterations: usize) !void {
    const allocation_size = 1024;
    const allocations_per_iter = 1000;
    
    // Benchmark GPA
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var j: usize = 0;
        var ptrs = try allocator.alloc([]u8, allocations_per_iter);
        defer allocator.free(ptrs);
        
        while (j < allocations_per_iter) : (j += 1) {
            ptrs[j] = try gpa_allocator.alloc(u8, allocation_size);
        }
        
        for (ptrs) |ptr| {
            gpa_allocator.free(ptr);
        }
    }
}

fn benchmarkArenaAllocator(allocator: *std.mem.Allocator, iterations: usize) !void {
    const allocation_size = 1024;
    const allocations_per_iter = 1000;
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var arena = std.heap.ArenaAllocator.init(allocator.*);
        defer arena.deinit();
        const arena_allocator = arena.allocator();
        
        var j: usize = 0;
        while (j < allocations_per_iter) : (j += 1) {
            _ = try arena_allocator.alloc(u8, allocation_size);
        }
        // All freed at once with arena.deinit()
    }
}

fn benchmarkSIMDDistance(allocator: *std.mem.Allocator, iterations: usize) !void {
    const vector_size = 200;
    
    var a = try allocator.alloc(f32, vector_size);
    defer allocator.free(a);
    var b = try allocator.alloc(f32, vector_size);
    defer allocator.free(b);
    
    // Initialize with random values
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    for (a) |*val| val.* = random.float(f32);
    for (b) |*val| val.* = random.float(f32);
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = simdEuclideanDistance(a, b);
    }
}

fn benchmarkScalarDistance(allocator: *std.mem.Allocator, iterations: usize) !void {
    const vector_size = 200;
    
    var a = try allocator.alloc(f32, vector_size);
    defer allocator.free(a);
    var b = try allocator.alloc(f32, vector_size);
    defer allocator.free(b);
    
    // Initialize with random values
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    for (a) |*val| val.* = random.float(f32);
    for (b) |*val| val.* = random.float(f32);
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var sum: f32 = 0;
        for (a, b) |val_a, val_b| {
            const diff = val_a - val_b;
            sum += diff * diff;
        }
        _ = @sqrt(sum);
    }
}

fn simdEuclideanDistance(a: []const f32, b: []const f32) f32 {
    const vec_size = std.simd.suggestVectorLength(f32) orelse 4;
    var sum: f32 = 0;
    
    var i: usize = 0;
    while (i + vec_size <= a.len) : (i += vec_size) {
        const va: @Vector(vec_size, f32) = a[i..][0..vec_size].*;
        const vb: @Vector(vec_size, f32) = b[i..][0..vec_size].*;
        const diff = va - vb;
        const squared = diff * diff;
        sum += @reduce(.Add, squared);
    }
    
    while (i < a.len) : (i += 1) {
        const diff = a[i] - b[i];
        sum += diff * diff;
    }
    
    return @sqrt(sum);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n{s}\n", .{"=" ** 80});
    std.debug.print("⚡ POKER CLUSTERING PERFORMANCE BENCHMARK SUITE ⚡\n", .{});
    std.debug.print("{s}\n", .{"=" ** 80});
    
    var suite = BenchmarkSuite.init(allocator);
    defer suite.deinit();
    
    // CPU Information
    std.debug.print("\n📊 System Information:\n", .{});
    std.debug.print("  Architecture: {s}\n", .{@tagName(builtin.cpu.arch)});
    std.debug.print("  CPU Model: {s}\n", .{builtin.cpu.model.name});
    std.debug.print("  Thread Count: {}\n", .{try std.Thread.getCpuCount()});
    
    const has_avx2 = if (builtin.cpu.arch == .x86_64) 
        std.Target.x86.cpu.Feature.avx2.isEnabled(builtin.cpu.features)
    else false;
    
    const has_simd = std.simd.suggestVectorLength(f32) != null;
    
    std.debug.print("  SIMD Support: {}\n", .{has_simd});
    std.debug.print("  AVX2: {}\n", .{has_avx2});
    
    std.debug.print("\n🏃 Running benchmarks...\n", .{});
    
    // EHS Calculation Benchmarks
    std.debug.print("\n1️⃣ EHS Calculation\n", .{});
    try suite.runBenchmark("Original EHS (baseline)", 1000, benchmarkOriginalEHS, true);
    try suite.runBenchmark("Optimized EHS (single)", 1000, benchmarkOptimizedEHS, false);
    try suite.runBenchmark("Optimized EHS (parallel)", 100, benchmarkParallelEHS, false);
    
    // Memory Allocator Benchmarks
    std.debug.print("\n2️⃣ Memory Allocators\n", .{});
    try suite.runBenchmark("GPA Allocator (baseline)", 100, benchmarkMemoryAllocators, true);
    try suite.runBenchmark("Arena Allocator", 100, benchmarkArenaAllocator, false);
    
    // Distance Calculation Benchmarks
    std.debug.print("\n3️⃣ Distance Calculations\n", .{});
    try suite.runBenchmark("Scalar Distance (baseline)", 100000, benchmarkScalarDistance, true);
    try suite.runBenchmark("SIMD Distance", 100000, benchmarkSIMDDistance, false);
    
    // Print results
    suite.printResults();
    
    // Summary
    std.debug.print("\n📈 Performance Summary:\n", .{});
    var total_speedup: f64 = 0;
    var count: usize = 0;
    
    for (suite.results.items) |result| {
        if (result.speedup > 0 and result.speedup != 1.0) {
            total_speedup += result.speedup;
            count += 1;
        }
    }
    
    if (count > 0) {
        const avg_speedup = total_speedup / @as(f64, @floatFromInt(count));
        std.debug.print("  Average speedup: {d:.2}x\n", .{avg_speedup});
        
        // Estimate time savings for full run
        const baseline_river_time = 600; // 10 minutes in seconds
        const baseline_turn_time = 1800; // 30 minutes
        const baseline_flop_time = 7200; // 120 minutes
        const total_baseline = baseline_river_time + baseline_turn_time + baseline_flop_time;
        
        const optimized_total = total_baseline / avg_speedup;
        const time_saved = total_baseline - optimized_total;
        
        std.debug.print("\n⏱️ Estimated Time Savings:\n", .{});
        std.debug.print("  Baseline total: {} minutes\n", .{total_baseline / 60});
        std.debug.print("  Optimized total: {d:.1} minutes\n", .{optimized_total / 60});
        std.debug.print("  Time saved: {d:.1} minutes ({d:.0}% reduction)\n", .{
            time_saved / 60,
            (time_saved / total_baseline) * 100,
        });
    }
    
    std.debug.print("\n✅ Benchmark suite complete!\n", .{});
}