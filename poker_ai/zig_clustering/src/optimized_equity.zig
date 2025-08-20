const std = @import("std");
const builtin = @import("builtin");
const Card = @import("eval_card.zig").Card;
const HandEvaluator = @import("evaluator.zig").HandEvaluator;

// SIMD-optimized equity calculator
pub const OptimizedEquityCalculator = struct {
    allocator: std.mem.Allocator,
    evaluator: HandEvaluator,
    
    // Pre-allocated buffers for batch processing
    batch_size: usize,
    opp_hands_buffer: [][]Card,
    results_buffer: []f32,
    
    // Thread-local random number generators
    prngs: []std.Random.DefaultPrng,
    
    pub fn init(allocator: std.mem.Allocator, batch_size: usize, n_threads: usize) !OptimizedEquityCalculator {
        const opp_hands_buffer = try allocator.alloc([]Card, batch_size);
        for (opp_hands_buffer) |*hand| {
            hand.* = try allocator.alloc(Card, 2);
        }
        
        const results_buffer = try allocator.alloc(f32, batch_size);
        
        const prngs = try allocator.alloc(std.Random.DefaultPrng, n_threads);
        for (prngs, 0..) |*prng, i| {
            prng.* = std.Random.DefaultPrng.init(42 + i);
        }
        
        return OptimizedEquityCalculator{
            .allocator = allocator,
            .evaluator = HandEvaluator{},
            .batch_size = batch_size,
            .opp_hands_buffer = opp_hands_buffer,
            .results_buffer = results_buffer,
            .prngs = prngs,
        };
    }
    
    pub fn deinit(self: *OptimizedEquityCalculator) void {
        for (self.opp_hands_buffer) |hand| {
            self.allocator.free(hand);
        }
        self.allocator.free(self.opp_hands_buffer);
        self.allocator.free(self.results_buffer);
        self.allocator.free(self.prngs);
    }
    
    // Vectorized EHS calculation with batching
    pub fn calculateEHSBatch(
        self: *OptimizedEquityCalculator,
        hands: []const []const Card,
        boards: []const []const Card,
        all_cards: []const Card,
        n_simulations: u32,
        thread_id: usize,
    ) ![]f32 {
        const n_hands = hands.len;
        var results = try self.allocator.alloc(f32, n_hands);
        
        // Process hands in chunks for better cache locality
        const chunk_size = 16; // Process 16 hands at a time
        var chunk_start: usize = 0;
        
        while (chunk_start < n_hands) : (chunk_start += chunk_size) {
            const chunk_end = @min(chunk_start + chunk_size, n_hands);
            
            // Calculate EHS for this chunk
            for (hands[chunk_start..chunk_end], boards[chunk_start..chunk_end], results[chunk_start..chunk_end]) |hand, board, *result| {
                result.* = try self.calculateEHSOptimized(hand, board, all_cards, n_simulations, thread_id);
            }
        }
        
        return results;
    }
    
    // Optimized single EHS calculation
    pub fn calculateEHSOptimized(
        self: *OptimizedEquityCalculator,
        our_hand: []const Card,
        board: []const Card,
        all_cards: []const Card,
        n_simulations: u32,
        thread_id: usize,
    ) !f32 {
        // Get available cards (excluding our hand and board)
        const available = try self.getAvailableCardsFast(our_hand, board, all_cards);
        defer self.allocator.free(available);
        
        if (available.len < 2) return 0.5;
        
        // Use thread-local PRNG
        const random = self.prngs[thread_id % self.prngs.len].random();
        
        // Process simulations in batches for better vectorization
        const sim_batch_size = @min(self.batch_size, n_simulations);
        var total_wins: f32 = 0;
        var total_sims: u32 = 0;
        
        while (total_sims < n_simulations) {
            const batch_size = @min(sim_batch_size, n_simulations - total_sims);
            
            // Generate batch of opponent hands
            for (self.opp_hands_buffer[0..batch_size]) |opp_hand| {
                const idx1 = random.intRangeLessThan(usize, 0, available.len);
                var idx2 = random.intRangeLessThan(usize, 0, available.len);
                while (idx2 == idx1) {
                    idx2 = random.intRangeLessThan(usize, 0, available.len);
                }
                opp_hand[0] = available[idx1];
                opp_hand[1] = available[idx2];
            }
            
            // Batch evaluate (this could be further optimized with SIMD in the evaluator)
            var batch_wins: f32 = 0;
            for (self.opp_hands_buffer[0..batch_size]) |opp_hand| {
                const result = HandEvaluator.compareHands(our_hand, opp_hand, board);
                if (result == 0) {
                    batch_wins += 1.0;
                } else if (result == 2) {
                    batch_wins += 0.5;
                }
            }
            
            total_wins += batch_wins;
            total_sims += batch_size;
        }
        
        return total_wins / @as(f32, @floatFromInt(total_sims));
    }
    
    // Fast available cards calculation with bit manipulation
    fn getAvailableCardsFast(
        self: *OptimizedEquityCalculator,
        our_hand: []const Card,
        board: []const Card,
        all_cards: []const Card,
    ) ![]Card {
        // Use a 64-bit mask for 52 cards
        var used_mask: u64 = 0;
        
        // Mark our hand cards as used
        for (our_hand) |card| {
            const card_idx = getCardIndex(card);
            used_mask |= @as(u64, 1) << @intCast(card_idx);
        }
        
        // Mark board cards as used
        for (board) |card| {
            const card_idx = getCardIndex(card);
            used_mask |= @as(u64, 1) << @intCast(card_idx);
        }
        
        // Count available cards using popcount
        const n_available = 52 - @popCount(used_mask);
        var available = try self.allocator.alloc(Card, n_available);
        
        // Fill available cards
        var idx: usize = 0;
        for (all_cards, 0..) |card, i| {
            if ((used_mask & (@as(u64, 1) << @intCast(i))) == 0) {
                available[idx] = card;
                idx += 1;
            }
        }
        
        return available;
    }
    
    fn getCardIndex(card: Card) usize {
        // Assuming cards are indexed 0-51 based on rank and suit
        const suit_idx = switch (card.suit[0]) {
            's' => 0,
            'h' => 1,
            'd' => 2,
            'c' => 3,
            else => 0,
        };
        return (card.rank - 2) * 4 + suit_idx;
    }
    
    // SIMD-optimized distribution calculation
    pub fn calculateDistributionSIMD(
        self: *OptimizedEquityCalculator,
        our_hand: []const Card,
        board: []const Card,
        all_cards: []const Card,
        n_next_cards: usize,
        n_clusters: usize,
        cluster_map: ?std.AutoHashMap(u64, u32),
        n_simulations: u32,
        thread_id: usize,
    ) ![]f32 {
        // Allocate aligned distribution array for SIMD
        const aligned_size = (n_clusters + 15) & ~@as(usize, 15);
        var distribution = try self.allocator.alignedAlloc(f32, 16, aligned_size);
        @memset(distribution, 0);
        
        const available = try self.getAvailableCardsFast(our_hand, board, all_cards);
        defer self.allocator.free(available);
        
        if (available.len < n_next_cards) {
            // Uniform distribution
            const uniform_val = 1.0 / @as(f32, @floatFromInt(n_clusters));
            @memset(distribution[0..n_clusters], uniform_val);
            return distribution[0..n_clusters];
        }
        
        const random = self.prngs[thread_id % self.prngs.len].random();
        const n_samples = @min(n_simulations, available.len);
        
        // Batch process samples
        const sample_batch_size = 32;
        var sample: u32 = 0;
        
        while (sample < n_samples) : (sample += sample_batch_size) {
            const batch_end = @min(sample + sample_batch_size, n_samples);
            const actual_batch = batch_end - sample;
            
            // Generate batch of next cards
            for (0..actual_batch) |_| {
                // Sample next cards
                var next_cards = try self.allocator.alloc(Card, n_next_cards);
                defer self.allocator.free(next_cards);
                
                var used = std.bit_set.IntegerBitSet(64).initEmpty();
                for (next_cards) |*card| {
                    var idx = random.intRangeLessThan(usize, 0, available.len);
                    while (used.isSet(idx)) {
                        idx = random.intRangeLessThan(usize, 0, available.len);
                    }
                    card.* = available[idx];
                    used.set(idx);
                }
                
                // Create new board
                var new_board = try self.allocator.alloc(Card, board.len + n_next_cards);
                defer self.allocator.free(new_board);
                
                @memcpy(new_board[0..board.len], board);
                @memcpy(new_board[board.len..], next_cards);
                
                // Calculate EHS for this scenario
                const ehs = try self.calculateEHSOptimized(our_hand, new_board, all_cards, 10, thread_id);
                
                // Map to cluster
                const cluster_id = if (cluster_map) |map| blk: {
                    const combo_hash = try hashCombo(our_hand, new_board);
                    break :blk map.get(combo_hash) orelse 0;
                } else blk: {
                    const bucket = @min(
                        @as(u32, @intFromFloat(ehs * @as(f32, @floatFromInt(n_clusters)))),
                        @as(u32, @intCast(n_clusters - 1)),
                    );
                    break :blk bucket;
                };
                
                distribution[cluster_id] += 1.0;
            }
        }
        
        // Normalize distribution using SIMD
        const sum = simdSum(distribution[0..n_clusters]);
        if (sum > 0) {
            simdNormalize(distribution[0..n_clusters], sum);
        }
        
        return distribution[0..n_clusters];
    }
    
    // SIMD helper functions
    fn simdSum(data: []f32) f32 {
        const vec_size = std.simd.suggestVectorLength(f32) orelse 4;
        var sum: f32 = 0;
        
        var i: usize = 0;
        while (i + vec_size <= data.len) : (i += vec_size) {
            const vec: @Vector(vec_size, f32) = data[i..][0..vec_size].*;
            sum += @reduce(.Add, vec);
        }
        
        // Handle remaining elements
        while (i < data.len) : (i += 1) {
            sum += data[i];
        }
        
        return sum;
    }
    
    fn simdNormalize(data: []f32, divisor: f32) void {
        const vec_size = std.simd.suggestVectorLength(f32) orelse 4;
        const div_vec: @Vector(vec_size, f32) = @splat(divisor);
        
        var i: usize = 0;
        while (i + vec_size <= data.len) : (i += vec_size) {
            const vec: @Vector(vec_size, f32) = data[i..][0..vec_size].*;
            data[i..][0..vec_size].* = vec / div_vec;
        }
        
        // Handle remaining elements
        while (i < data.len) : (i += 1) {
            data[i] /= divisor;
        }
    }
    
    fn hashCombo(hand: []const Card, board: []const Card) !u64 {
        var hash: u64 = 0;
        
        // Hash hand cards
        for (hand) |card| {
            hash = hash *% 31 + @as(u64, card.rank);
            hash = hash *% 31 + @as(u64, card.suit[0]);
        }
        
        // Hash board cards
        for (board) |card| {
            hash = hash *% 31 + @as(u64, card.rank);
            hash = hash *% 31 + @as(u64, card.suit[0]);
        }
        
        return hash;
    }
};

// Parallel EHS calculator for multiple threads
pub const ParallelEHSCalculator = struct {
    calculators: []OptimizedEquityCalculator,
    allocator: std.mem.Allocator,
    n_threads: usize,
    
    pub fn init(allocator: std.mem.Allocator, n_threads: usize, batch_size: usize) !ParallelEHSCalculator {
        const calculators = try allocator.alloc(OptimizedEquityCalculator, n_threads);
        for (calculators, 0..) |*calc, i| {
            calc.* = try OptimizedEquityCalculator.init(allocator, batch_size, n_threads);
        }
        
        return ParallelEHSCalculator{
            .calculators = calculators,
            .allocator = allocator,
            .n_threads = n_threads,
        };
    }
    
    pub fn deinit(self: *ParallelEHSCalculator) void {
        for (self.calculators) |*calc| {
            calc.deinit();
        }
        self.allocator.free(self.calculators);
    }
    
    // Process multiple hands in parallel
    pub fn processBatch(
        self: *ParallelEHSCalculator,
        hands: []const []const Card,
        boards: []const []const Card,
        all_cards: []const Card,
        n_simulations: u32,
    ) ![]f32 {
        const n_hands = hands.len;
        const results = try self.allocator.alloc(f32, n_hands);
        
        // Divide work among threads
        const chunk_size = (n_hands + self.n_threads - 1) / self.n_threads;
        
        const ThreadContext = struct {
            calc: *OptimizedEquityCalculator,
            hands: []const []const Card,
            boards: []const []const Card,
            all_cards: []const Card,
            results: []f32,
            n_simulations: u32,
            thread_id: usize,
        };
        
        var contexts = try self.allocator.alloc(ThreadContext, self.n_threads);
        defer self.allocator.free(contexts);
        
        var threads = try self.allocator.alloc(std.Thread, self.n_threads);
        defer self.allocator.free(threads);
        
        // Launch threads
        for (0..self.n_threads) |i| {
            const start = i * chunk_size;
            if (start >= n_hands) break;
            
            const end = @min(start + chunk_size, n_hands);
            
            contexts[i] = .{
                .calc = &self.calculators[i],
                .hands = hands[start..end],
                .boards = boards[start..end],
                .all_cards = all_cards,
                .results = results[start..end],
                .n_simulations = n_simulations,
                .thread_id = i,
            };
            
            threads[i] = try std.Thread.spawn(.{}, processThread, .{&contexts[i]});
        }
        
        // Wait for threads
        for (threads[0..@min(self.n_threads, (n_hands + chunk_size - 1) / chunk_size)]) |thread| {
            thread.join();
        }
        
        return results;
    }
    
    fn processThread(ctx: *const anytype) void {
        const batch_results = ctx.calc.calculateEHSBatch(
            ctx.hands,
            ctx.boards,
            ctx.all_cards,
            ctx.n_simulations,
            ctx.thread_id,
        ) catch return;
        defer ctx.calc.allocator.free(batch_results);
        
        @memcpy(ctx.results, batch_results);
    }
};

// Benchmark function to test optimizations
pub fn benchmarkEquityCalculator(allocator: std.mem.Allocator) !void {
    std.debug.print("\n{s}\n", .{"=" ** 60});
    std.debug.print("Equity Calculator Performance Benchmark\n", .{});
    std.debug.print("{s}\n", .{"=" ** 60});
    
    const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
    defer allocator.free(all_cards);
    
    // Create test hands and boards
    const n_test_hands = 1000;
    var hands = try allocator.alloc([]Card, n_test_hands);
    defer {
        for (hands) |hand| allocator.free(hand);
        allocator.free(hands);
    }
    
    var boards = try allocator.alloc([]Card, n_test_hands);
    defer {
        for (boards) |board| allocator.free(board);
        allocator.free(boards);
    }
    
    // Generate random hands and boards
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    for (hands, boards) |*hand, *board| {
        hand.* = try allocator.alloc(Card, 2);
        board.* = try allocator.alloc(Card, 5);
        
        // Random hand
        const h1 = random.intRangeLessThan(usize, 0, 52);
        var h2 = random.intRangeLessThan(usize, 0, 52);
        while (h2 == h1) h2 = random.intRangeLessThan(usize, 0, 52);
        hand.*[0] = all_cards[h1];
        hand.*[1] = all_cards[h2];
        
        // Random board
        var used = std.bit_set.IntegerBitSet(64).initEmpty();
        used.set(h1);
        used.set(h2);
        
        for (board.*) |*card| {
            var idx = random.intRangeLessThan(usize, 0, 52);
            while (used.isSet(idx)) {
                idx = random.intRangeLessThan(usize, 0, 52);
            }
            card.* = all_cards[idx];
            used.set(idx);
        }
    }
    
    // Benchmark single-threaded optimized
    {
        var calc = try OptimizedEquityCalculator.init(allocator, 32, 1);
        defer calc.deinit();
        
        const start = std.time.nanoTimestamp();
        
        for (hands[0..100], boards[0..100]) |hand, board| {
            _ = try calc.calculateEHSOptimized(hand, board, all_cards, 100, 0);
        }
        
        const elapsed = std.time.nanoTimestamp() - start;
        std.debug.print("\nSingle-threaded (100 hands, 100 sims each):\n", .{});
        std.debug.print("  Time: {} ms\n", .{elapsed / 1000000});
        std.debug.print("  Throughput: {} hands/sec\n", .{100 * 1000000000 / elapsed});
    }
    
    // Benchmark multi-threaded
    {
        var calc = try ParallelEHSCalculator.init(allocator, 8, 32);
        defer calc.deinit();
        
        const start = std.time.nanoTimestamp();
        
        const results = try calc.processBatch(hands[0..100], boards[0..100], all_cards, 100);
        defer allocator.free(results);
        
        const elapsed = std.time.nanoTimestamp() - start;
        std.debug.print("\nMulti-threaded (8 threads, 100 hands, 100 sims each):\n", .{});
        std.debug.print("  Time: {} ms\n", .{elapsed / 1000000});
        std.debug.print("  Throughput: {} hands/sec\n", .{100 * 1000000000 / elapsed});
    }
    
    std.debug.print("\n✅ Benchmark complete!\n", .{});
}