const std = @import("std");
const Card = @import("eval_card.zig").Card;
const EquityCalculator = @import("equity_calculator.zig").EquityCalculator;
const Storage = @import("storage.zig").Storage;

// LUT Builder - Creates lookup tables for hand abstraction
pub const LUTBuilder = struct {
    allocator: std.mem.Allocator,
    storage: *Storage,
    equity_calc: EquityCalculator,
    all_cards: []Card,
    
    // Clustering parameters
    n_river_clusters: usize,
    n_turn_clusters: usize,
    n_flop_clusters: usize,
    n_preflop_clusters: usize,
    
    // Coverage limits
    max_river_combos: usize,
    max_turn_combos: usize,
    max_flop_combos: usize,
    
    // Simulation parameters
    n_simulations_river: u32,
    n_simulations_turn: u32,
    n_simulations_flop: u32,
    
    // LUTs - map from combo hash to cluster ID
    river_lut: std.AutoHashMap(u64, u32),
    turn_lut: std.AutoHashMap(u64, u32),
    flop_lut: std.AutoHashMap(u64, u32),
    preflop_lut: std.AutoHashMap(u64, u32),
    
    pub fn init(
        allocator: std.mem.Allocator,
        storage: *Storage,
        n_river_clusters: usize,
        n_turn_clusters: usize,
        n_flop_clusters: usize,
        n_preflop_clusters: usize,
    ) !LUTBuilder {
        const all_cards = try @import("eval_card.zig").generateAllCards(allocator);
        
        return LUTBuilder{
            .allocator = allocator,
            .storage = storage,
            .equity_calc = EquityCalculator.init(allocator),
            .all_cards = all_cards,
            .n_river_clusters = n_river_clusters,
            .n_turn_clusters = n_turn_clusters,
            .n_flop_clusters = n_flop_clusters,
            .n_preflop_clusters = n_preflop_clusters,
            .max_river_combos = 1000,  // Default, will be overridden
            .max_turn_combos = 1000,
            .max_flop_combos = 1000,
            .n_simulations_river = 100,
            .n_simulations_turn = 50,
            .n_simulations_flop = 25,
            .river_lut = std.AutoHashMap(u64, u32).init(allocator),
            .turn_lut = std.AutoHashMap(u64, u32).init(allocator),
            .flop_lut = std.AutoHashMap(u64, u32).init(allocator),
            .preflop_lut = std.AutoHashMap(u64, u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *LUTBuilder) void {
        self.allocator.free(self.all_cards);
        self.river_lut.deinit();
        self.turn_lut.deinit();
        self.flop_lut.deinit();
        self.preflop_lut.deinit();
    }
    
    // Build River LUT
    pub fn buildRiverLUT(self: *LUTBuilder) !void {
        std.debug.print("\n{s}\n", .{"=" ** 60});
        std.debug.print("Building RIVER LUT\n", .{});
        std.debug.print("{s}\n", .{"=" ** 60});
        
        // Generate river combinations (2 hole + 5 board)
        const combos = try self.generateRiverCombinations();
        defer {
            // Free individual hand and board allocations
            for (combos) |combo| {
                self.allocator.free(combo.hand);
                self.allocator.free(combo.board);
            }
            self.allocator.free(combos);
        }
        
        std.debug.print("Generated {} river combinations\n", .{combos.len});
        
        // Extract features (EHS values)
        var features = try self.allocator.alloc([]f32, combos.len);
        defer {
            for (features) |feature| {
                self.allocator.free(feature);
            }
            self.allocator.free(features);
        }
        
        for (combos, 0..) |combo, i| {
            const hand = combo.hand;
            const board = combo.board;
            
            // Calculate EHS
            const ehs = try self.equity_calc.calculateEHS(
                hand,
                board,
                self.all_cards,
                self.n_simulations_river,
                42 + @as(u64, i),
            );
            
            // Feature is just the EHS value
            features[i] = try self.allocator.alloc(f32, 1);
            features[i][0] = ehs;
            
            // Store in database
            try self.storage.storeRiverData(@intCast(i), combo, ehs, null);
            
            if (i % 100 == 0) {
                try self.storage.flush();
                std.debug.print("  Processed {}/{} river combos\n", .{ i, combos.len });
            }
        }
        
        // Cluster using K-means
        std.debug.print("Clustering river combinations...\n", .{});
        var kmeans = try KMeans.init(self.allocator, self.n_river_clusters, 1);
        defer kmeans.deinit();
        
        try kmeans.fit(features);
        
        // Assign clusters and build LUT
        for (combos, 0..) |combo, i| {
            const cluster_id = kmeans.predict(features[i]);
            
            // Update database
            try self.storage.updateClusterId("river", @intCast(i), @intCast(cluster_id));
            
            // Add to LUT
            const hash = try self.equity_calc.hashCombo(combo.hand, combo.board);
            try self.river_lut.put(hash, @intCast(cluster_id));
        }
        
        try self.storage.flush();
        std.debug.print("✅ River LUT complete: {} entries\n", .{self.river_lut.count()});
    }
    
    // Build Turn LUT
    pub fn buildTurnLUT(self: *LUTBuilder) !void {
        std.debug.print("\n{s}\n", .{"=" ** 60});
        std.debug.print("Building TURN LUT\n", .{});
        std.debug.print("{s}\n", .{"=" ** 60});
        
        // Generate turn combinations (2 hole + 4 board)
        const combos = try self.generateTurnCombinations();
        defer {
            // Free individual hand and board allocations
            for (combos) |combo| {
                self.allocator.free(combo.hand);
                self.allocator.free(combo.board);
            }
            self.allocator.free(combos);
        }
        
        std.debug.print("Generated {} turn combinations\n", .{combos.len});
        
        // Extract features (distribution over river clusters)
        var features = try self.allocator.alloc([]f32, combos.len);
        defer {
            for (features) |feature| {
                self.allocator.free(feature);
            }
            self.allocator.free(features);
        }
        
        for (combos, 0..) |combo, i| {
            const hand = combo.hand;
            const board = combo.board;
            
            // Calculate distribution over river clusters
            const distribution = try self.equity_calc.calculateDistribution(
                hand,
                board,
                self.all_cards,
                1, // Add 1 card for river
                self.n_river_clusters,
                self.river_lut,
                self.n_simulations_turn,
                42 + @as(u64, i),
            );
            
            features[i] = distribution;
            
            // Store in database
            try self.storage.storeTurnData(@intCast(i), combo, distribution, null);
            
            if (i % 100 == 0) {
                try self.storage.flush();
                std.debug.print("  Processed {}/{} turn combos\n", .{ i, combos.len });
            }
        }
        
        // Cluster using K-means
        std.debug.print("Clustering turn combinations...\n", .{});
        var kmeans = try KMeans.init(self.allocator, self.n_turn_clusters, self.n_river_clusters);
        defer kmeans.deinit();
        
        try kmeans.fit(features);
        
        // Assign clusters and build LUT
        for (combos, 0..) |combo, i| {
            const cluster_id = kmeans.predict(features[i]);
            
            // Update database
            try self.storage.updateClusterId("turn", @intCast(i), @intCast(cluster_id));
            
            // Add to LUT
            const hash = try self.equity_calc.hashCombo(combo.hand, combo.board);
            try self.turn_lut.put(hash, @intCast(cluster_id));
        }
        
        try self.storage.flush();
        std.debug.print("✅ Turn LUT complete: {} entries\n", .{self.turn_lut.count()});
    }
    
    // Build Flop LUT
    pub fn buildFlopLUT(self: *LUTBuilder) !void {
        std.debug.print("\n{s}\n", .{"=" ** 60});
        std.debug.print("Building FLOP LUT\n", .{});
        std.debug.print("{s}\n", .{"=" ** 60});
        
        // Generate flop combinations (2 hole + 3 board)
        const combos = try self.generateFlopCombinations();
        defer {
            // Free individual hand and board allocations
            for (combos) |combo| {
                self.allocator.free(combo.hand);
                self.allocator.free(combo.board);
            }
            self.allocator.free(combos);
        }
        
        std.debug.print("Generated {} flop combinations\n", .{combos.len});
        
        // Extract features (distribution over turn clusters)
        var features = try self.allocator.alloc([]f32, combos.len);
        defer {
            for (features) |feature| {
                self.allocator.free(feature);
            }
            self.allocator.free(features);
        }
        
        for (combos, 0..) |combo, i| {
            const hand = combo.hand;
            const board = combo.board;
            
            // Calculate distribution over turn clusters
            const distribution = try self.equity_calc.calculateDistribution(
                hand,
                board,
                self.all_cards,
                1, // Add 1 card for turn
                self.n_turn_clusters,
                self.turn_lut,
                self.n_simulations_flop,
                42 + @as(u64, i),
            );
            
            features[i] = distribution;
            
            // Store in database
            try self.storage.storeFlopData(@intCast(i), combo, distribution, null);
            
            if (i % 100 == 0) {
                try self.storage.flush();
                std.debug.print("  Processed {}/{} flop combos\n", .{ i, combos.len });
            }
        }
        
        // Cluster using K-means
        std.debug.print("Clustering flop combinations...\n", .{});
        var kmeans = try KMeans.init(self.allocator, self.n_flop_clusters, self.n_turn_clusters);
        defer kmeans.deinit();
        
        try kmeans.fit(features);
        
        // Assign clusters and build LUT
        for (combos, 0..) |combo, i| {
            const cluster_id = kmeans.predict(features[i]);
            
            // Update database
            try self.storage.updateClusterId("flop", @intCast(i), @intCast(cluster_id));
            
            // Add to LUT
            const hash = try self.equity_calc.hashCombo(combo.hand, combo.board);
            try self.flop_lut.put(hash, @intCast(cluster_id));
        }
        
        try self.storage.flush();
        std.debug.print("✅ Flop LUT complete: {} entries\n", .{self.flop_lut.count()});
    }
    
    // Combination generation
    pub const Combination = struct {
        hand: []Card,   // 2 cards
        board: []Card,  // 3-5 cards
    };
    
    fn generateRiverCombinations(self: *LUTBuilder) ![]Combination {
        // Generate river combinations up to max_river_combos limit
        // Full coverage would be C(52,2) * C(50,5) = 2.8 billion combinations
        var combos = std.ArrayList(Combination).init(self.allocator);
        
        const max_combos = self.max_river_combos;
        var count: usize = 0;
        
        // Calculate skip factor for uniform sampling (for future use)
        // const total_possible = (52 * 51 / 2) * (50 * 49 * 48 * 47 * 46 / (5 * 4 * 3 * 2 * 1));
        // const skip_factor = @max(1, total_possible / max_combos);
        
        // Generate hand combinations
        var i: usize = 0;
        while (i < self.all_cards.len - 1 and count < max_combos) : (i += 1) {
            var j = i + 1;
            while (j < self.all_cards.len and count < max_combos) : (j += 1) {
                // Generate board combinations
                var b1: usize = 0;
                while (b1 < self.all_cards.len - 4 and count < max_combos) : (b1 += 1) {
                    if (b1 == i or b1 == j) continue;
                    
                    var b2 = b1 + 1;
                    while (b2 < self.all_cards.len - 3 and count < max_combos) : (b2 += 1) {
                        if (b2 == i or b2 == j) continue;
                        
                        var b3 = b2 + 1;
                        while (b3 < self.all_cards.len - 2 and count < max_combos) : (b3 += 1) {
                            if (b3 == i or b3 == j) continue;
                            
                            var b4 = b3 + 1;
                            while (b4 < self.all_cards.len - 1 and count < max_combos) : (b4 += 1) {
                                if (b4 == i or b4 == j) continue;
                                
                                var b5 = b4 + 1;
                                while (b5 < self.all_cards.len and count < max_combos) : (b5 += 1) {
                                    if (b5 == i or b5 == j) continue;
                                    
                                    const hand = try self.allocator.alloc(Card, 2);
                                    hand[0] = self.all_cards[i];
                                    hand[1] = self.all_cards[j];
                                    
                                    const board = try self.allocator.alloc(Card, 5);
                                    board[0] = self.all_cards[b1];
                                    board[1] = self.all_cards[b2];
                                    board[2] = self.all_cards[b3];
                                    board[3] = self.all_cards[b4];
                                    board[4] = self.all_cards[b5];
                                    
                                    try combos.append(Combination{
                                        .hand = hand,
                                        .board = board,
                                    });
                                    
                                    count += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return combos.toOwnedSlice();
    }
    
    fn generateTurnCombinations(self: *LUTBuilder) ![]Combination {
        // Generate turn combinations up to max_turn_combos limit
        // Full coverage would be C(52,2) * C(50,4) = 305 million combinations
        var combos = std.ArrayList(Combination).init(self.allocator);
        
        const max_combos = self.max_turn_combos;
        var count: usize = 0;
        
        // Generate hand combinations
        var i: usize = 0;
        while (i < self.all_cards.len - 1 and count < max_combos) : (i += 1) {
            var j = i + 1;
            while (j < self.all_cards.len and count < max_combos) : (j += 1) {
                // Generate board combinations (4 cards)
                var b1: usize = 0;
                while (b1 < self.all_cards.len - 3 and count < max_combos) : (b1 += 1) {
                    if (b1 == i or b1 == j) continue;
                    
                    var b2 = b1 + 1;
                    while (b2 < self.all_cards.len - 2 and count < max_combos) : (b2 += 1) {
                        if (b2 == i or b2 == j) continue;
                        
                        var b3 = b2 + 1;
                        while (b3 < self.all_cards.len - 1 and count < max_combos) : (b3 += 1) {
                            if (b3 == i or b3 == j) continue;
                            
                            var b4 = b3 + 1;
                            while (b4 < self.all_cards.len and count < max_combos) : (b4 += 1) {
                                if (b4 == i or b4 == j) continue;
                                
                                const hand = try self.allocator.alloc(Card, 2);
                                hand[0] = self.all_cards[i];
                                hand[1] = self.all_cards[j];
                                
                                const board = try self.allocator.alloc(Card, 4);
                                board[0] = self.all_cards[b1];
                                board[1] = self.all_cards[b2];
                                board[2] = self.all_cards[b3];
                                board[3] = self.all_cards[b4];
                                
                                try combos.append(Combination{
                                    .hand = hand,
                                    .board = board,
                                });
                                
                                count += 1;
                            }
                        }
                    }
                }
            }
        }
        
        return combos.toOwnedSlice();
    }
    
    fn generateFlopCombinations(self: *LUTBuilder) ![]Combination {
        // Generate flop combinations up to max_flop_combos limit
        // Full coverage would be C(52,2) * C(50,3) = 26 million combinations
        var combos = std.ArrayList(Combination).init(self.allocator);
        
        const max_combos = self.max_flop_combos;
        var count: usize = 0;
        
        // Generate hand combinations
        var i: usize = 0;
        while (i < self.all_cards.len - 1 and count < max_combos) : (i += 1) {
            var j = i + 1;
            while (j < self.all_cards.len and count < max_combos) : (j += 1) {
                // Generate board combinations (3 cards)
                var b1: usize = 0;
                while (b1 < self.all_cards.len - 2 and count < max_combos) : (b1 += 1) {
                    if (b1 == i or b1 == j) continue;
                    
                    var b2 = b1 + 1;
                    while (b2 < self.all_cards.len - 1 and count < max_combos) : (b2 += 1) {
                        if (b2 == i or b2 == j) continue;
                        
                        var b3 = b2 + 1;
                        while (b3 < self.all_cards.len and count < max_combos) : (b3 += 1) {
                            if (b3 == i or b3 == j) continue;
                            
                            const hand = try self.allocator.alloc(Card, 2);
                            hand[0] = self.all_cards[i];
                            hand[1] = self.all_cards[j];
                            
                            const board = try self.allocator.alloc(Card, 3);
                            board[0] = self.all_cards[b1];
                            board[1] = self.all_cards[b2];
                            board[2] = self.all_cards[b3];
                            
                            try combos.append(Combination{
                                .hand = hand,
                                .board = board,
                            });
                            
                            count += 1;
                        }
                    }
                }
            }
        }
        
        return combos.toOwnedSlice();
    }
};

// Mini-batch K-means implementation
pub const KMeans = struct {
    n_clusters: usize,
    n_features: usize,
    centroids: [][]f32,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, n_clusters: usize, n_features: usize) !KMeans {
        const centroids = try allocator.alloc([]f32, n_clusters);
        
        // Initialize centroids randomly
        var prng = std.Random.DefaultPrng.init(123);
        const random = prng.random();
        
        for (centroids) |*centroid| {
            centroid.* = try allocator.alloc(f32, n_features);
            for (centroid.*) |*val| {
                val.* = random.float(f32);
            }
        }
        
        return KMeans{
            .n_clusters = n_clusters,
            .n_features = n_features,
            .centroids = centroids,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *KMeans) void {
        for (self.centroids) |centroid| {
            self.allocator.free(centroid);
        }
        self.allocator.free(self.centroids);
    }
    
    pub fn fit(self: *KMeans, data: [][]f32) !void {
        const max_iterations = 100;
        const batch_size = @min(200, data.len / 10);
        
        var iter: usize = 0;
        while (iter < max_iterations) : (iter += 1) {
            // Mini-batch update
            var batch_start: usize = 0;
            while (batch_start < data.len) : (batch_start += batch_size) {
                const batch_end = @min(batch_start + batch_size, data.len);
                const batch = data[batch_start..batch_end];
                
                try self.partialFit(batch);
            }
        }
    }
    
    fn partialFit(self: *KMeans, batch: [][]f32) !void {
        // Count assignments
        var counts = try self.allocator.alloc(usize, self.n_clusters);
        defer self.allocator.free(counts);
        @memset(counts, 0);
        
        // Sum for new centroids
        var sums = try self.allocator.alloc([]f32, self.n_clusters);
        defer {
            for (sums) |sum| {
                self.allocator.free(sum);
            }
            self.allocator.free(sums);
        }
        
        for (sums) |*sum| {
            sum.* = try self.allocator.alloc(f32, self.n_features);
            @memset(sum.*, 0);
        }
        
        // Assign points and accumulate
        for (batch) |point| {
            const cluster = self.predict(point);
            counts[cluster] += 1;
            
            for (point, 0..) |val, i| {
                sums[cluster][i] += val;
            }
        }
        
        // Update centroids with learning rate
        const learning_rate: f32 = 0.1;
        for (self.centroids, 0..) |*centroid, c| {
            if (counts[c] > 0) {
                const count_f = @as(f32, @floatFromInt(counts[c]));
                for (centroid.*, 0..) |*val, i| {
                    const new_val = sums[c][i] / count_f;
                    val.* = val.* * (1.0 - learning_rate) + new_val * learning_rate;
                }
            }
        }
    }
    
    pub fn predict(self: *KMeans, point: []f32) usize {
        var min_dist: f32 = std.math.inf(f32);
        var best_cluster: usize = 0;
        
        for (self.centroids, 0..) |centroid, c| {
            const dist = euclideanDistance(point, centroid);
            if (dist < min_dist) {
                min_dist = dist;
                best_cluster = c;
            }
        }
        
        return best_cluster;
    }
    
    fn euclideanDistance(a: []const f32, b: []const f32) f32 {
        var sum: f32 = 0;
        for (a, b) |val_a, val_b| {
            const diff = val_a - val_b;
            sum += diff * diff;
        }
        return @sqrt(sum);
    }
};