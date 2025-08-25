const std = @import("std");
const io_helpers = @import("io_helpers.zig");const hand_eval = @import("hand_eval.zig");
const game_state = @import("game_state.zig");

// Constants for clustering configuration
pub const MAX_ITERATIONS = 100;
pub const CONVERGENCE_THRESHOLD = 0.001;
pub const DEFAULT_N_SIMULATIONS = 100;

// Preflop configuration
pub const PREFLOP_CANONICAL_HANDS = 169; // 13x13 matrix reduced by suit isomorphism
pub const DEFAULT_PREFLOP_CLUSTERS = 8;

// Postflop configuration
pub const DEFAULT_FLOP_CLUSTERS = 50;
pub const DEFAULT_TURN_CLUSTERS = 50;
pub const DEFAULT_RIVER_CLUSTERS = 50;

/// Hand features used for clustering
pub const HandFeatures = struct {
    /// Expected hand strength (EHS) - probability of winning at showdown
    ehs: f64,

    /// Hand strength squared - for variance calculation
    ehs2: f64,

    /// Positive potential - probability of improving to best hand
    positive_potential: f64,

    /// Negative potential - probability of being overtaken
    negative_potential: f64,

    /// Immediate hand strength (current rank normalized)
    immediate_strength: f64,

    /// Additional features for more sophisticated clustering
    draw_potential: f64, // Flush/straight draw potential
    nut_potential: f64, // Potential to make the nuts

    pub fn distance(self: HandFeatures, other: HandFeatures) f64 {
        // Euclidean distance with weighted features
        const ehs_weight = 1.0;
        const potential_weight = 0.5;
        const draw_weight = 0.3;

        var sum: f64 = 0.0;
        sum += std.math.pow(f64, (self.ehs - other.ehs) * ehs_weight, 2);
        sum += std.math.pow(f64, (self.positive_potential - other.positive_potential) * potential_weight, 2);
        sum += std.math.pow(f64, (self.negative_potential - other.negative_potential) * potential_weight, 2);
        sum += std.math.pow(f64, (self.draw_potential - other.draw_potential) * draw_weight, 2);

        return @sqrt(sum);
    }

    pub fn earthMoversDistance(self: HandFeatures, other: HandFeatures) f64 {
        // Earth Mover's Distance (EMD) - more sophisticated metric
        // Treats hand strength as a probability distribution
        const ehs_diff = @abs(self.ehs - other.ehs);
        const var_diff = @abs(self.ehs2 - self.ehs * self.ehs - (other.ehs2 - other.ehs * other.ehs));
        const potential_diff = @abs(self.positive_potential - other.positive_potential);

        return ehs_diff + 0.3 * var_diff + 0.2 * potential_diff;
    }
};

/// Feature extractor for poker hands
pub const FeatureExtractor = struct {
    evaluator: *hand_eval.HandEvaluator,
    allocator: std.mem.Allocator,
    n_simulations: u32,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        evaluator: *hand_eval.HandEvaluator,
        n_simulations: u32,
    ) Self {
        return Self{
            .allocator = allocator,
            .evaluator = evaluator,
            .n_simulations = n_simulations,
        };
    }

    /// Extract features for a hand on a given board
    pub fn extractFeatures(
        self: *Self,
        hole_cards: [2]hand_eval.Card,
        board: []const hand_eval.Card,
    ) !HandFeatures {
        var features = HandFeatures{
            .ehs = 0.0,
            .ehs2 = 0.0,
            .positive_potential = 0.0,
            .negative_potential = 0.0,
            .immediate_strength = 0.0,
            .draw_potential = 0.0,
            .nut_potential = 0.0,
        };

        // Calculate immediate hand strength
        const current_rank = self.evaluator.evaluate(hole_cards, board);
        features.immediate_strength = 1.0 - @as(f64, @floatFromInt(current_rank)) / @as(f64, hand_eval.MAX_HIGH_CARD);

        // Monte Carlo simulation for EHS and potential
        var wins: u32 = 0;
        var ties: u32 = 0;
        var total: u32 = 0;

        // Track potential outcomes
        var ahead_tied_behind = [3][3]u32{
            [3]u32{ 0, 0, 0 }, // ahead
            [3]u32{ 0, 0, 0 }, // tied
            [3]u32{ 0, 0, 0 }, // behind
        };

        // Create deck excluding known cards
        var deck = try std.ArrayList(hand_eval.Card).initCapacity(self.allocator, 0);
        defer deck.deinit(self.allocator);

        // Add all 52 cards initially
        for (0..52) |i| {
            const card = hand_eval.CardOps.fromIndex(@intCast(i));

            // Skip cards already in play
            var in_play = false;
            for (hole_cards) |hc| {
                if (hc == card) {
                    in_play = true;
                    break;
                }
            }
            for (board) |bc| {
                if (bc == card) {
                    in_play = true;
                    break;
                }
            }

            if (!in_play) {
                try deck.append(self.allocator, card);
            }
        }

        // Run simulations
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();

        for (0..self.n_simulations) |_| {
            // Sample opponent hole cards
            const opp_cards = try self.sampleOpponentCards(&deck, random);

            // Current street evaluation
            const our_current = self.evaluator.evaluate(hole_cards, board);
            const opp_current = self.evaluator.evaluate(opp_cards, board);

            const current_result: u8 = if (our_current < opp_current) 0 // ahead
                else if (our_current == opp_current) 1 // tied
                else 2; // behind

            // If not on river, simulate future streets
            if (board.len < 5) {
                const future_board = try self.sampleFutureBoard(&deck, board, opp_cards, random);
                defer self.allocator.free(future_board);

                const our_future = self.evaluator.evaluate(hole_cards, future_board);
                const opp_future = self.evaluator.evaluate(opp_cards, future_board);

                const future_result: u8 = if (our_future < opp_future) 0 // ahead
                    else if (our_future == opp_future) 1 // tied
                    else 2; // behind

                ahead_tied_behind[current_result][future_result] += 1;

                // Update EHS
                if (future_result == 0) wins += 1 else if (future_result == 1) ties += 1;
            } else {
                // On river, just use current evaluation
                if (current_result == 0) wins += 1 else if (current_result == 1) ties += 1;
            }

            total += 1;
        }

        // Calculate EHS and EHS2
        features.ehs = (@as(f64, @floatFromInt(wins)) + @as(f64, @floatFromInt(ties)) * 0.5) / @as(f64, @floatFromInt(total));
        features.ehs2 = features.ehs * features.ehs;

        // Calculate positive and negative potential
        if (board.len < 5) {
            const ahead = ahead_tied_behind[0][0] + ahead_tied_behind[0][1] + ahead_tied_behind[0][2];
            const tied = ahead_tied_behind[1][0] + ahead_tied_behind[1][1] + ahead_tied_behind[1][2];
            const behind = ahead_tied_behind[2][0] + ahead_tied_behind[2][1] + ahead_tied_behind[2][2];

            if (behind + tied > 0) {
                features.positive_potential = @as(f64, @floatFromInt(ahead_tied_behind[2][0] + ahead_tied_behind[1][0])) /
                    @as(f64, @floatFromInt(behind + tied));
            }

            if (ahead + tied > 0) {
                features.negative_potential = @as(f64, @floatFromInt(ahead_tied_behind[0][2] + ahead_tied_behind[1][2])) /
                    @as(f64, @floatFromInt(ahead + tied));
            }
        }

        // Calculate draw potential
        features.draw_potential = try self.calculateDrawPotential(hole_cards, board);

        // Calculate nut potential
        features.nut_potential = try self.calculateNutPotential(hole_cards, board);

        return features;
    }

    fn sampleOpponentCards(self: *Self, deck: *std.ArrayList(hand_eval.Card), random: std.Random) ![2]hand_eval.Card {
        _ = self;

        const idx1 = random.intRangeAtMost(usize, 0, deck.items.len - 1);
        var idx2 = random.intRangeAtMost(usize, 0, deck.items.len - 1);
        while (idx2 == idx1) {
            idx2 = random.intRangeAtMost(usize, 0, deck.items.len - 1);
        }

        return [2]hand_eval.Card{ deck.items[idx1], deck.items[idx2] };
    }

    fn sampleFutureBoard(
        self: *Self,
        deck: *std.ArrayList(hand_eval.Card),
        current_board: []const hand_eval.Card,
        opp_cards: [2]hand_eval.Card,
        random: std.Random,
    ) ![]hand_eval.Card {
        const cards_needed = 5 - current_board.len;
        var future_board = try self.allocator.alloc(hand_eval.Card, 5);

        // Copy current board
        @memcpy(future_board[0..current_board.len], current_board);

        // Sample remaining cards
        var available = try std.ArrayList(hand_eval.Card).initCapacity(self.allocator, 0);
        defer available.deinit(self.allocator);

        for (deck.items) |card| {
            if (card != opp_cards[0] and card != opp_cards[1]) {
                try available.append(self.allocator, card);
            }
        }

        for (0..cards_needed) |i| {
            const idx = random.intRangeAtMost(usize, 0, available.items.len - 1);
            future_board[current_board.len + i] = available.orderedRemove(idx);
        }

        return future_board;
    }

    fn calculateDrawPotential(self: *Self, hole_cards: [2]hand_eval.Card, board: []const hand_eval.Card) !f64 {
        _ = self;

        if (board.len >= 5) return 0.0; // No draws on river

        // Check for flush draws
        var suits = [4]u8{ 0, 0, 0, 0 };
        for (hole_cards) |card| {
            const suit_bits = (card >> 12) & 0xF;
            // Convert bit pattern to index (1->0, 2->1, 4->2, 8->3)
            const suit_idx: usize = switch (suit_bits) {
                1 => 0, // Spades
                2 => 1, // Hearts
                4 => 2, // Diamonds
                8 => 3, // Clubs
                else => 0, // Default to spades if invalid
            };
            suits[suit_idx] += 1;
        }
        for (board) |card| {
            const suit_bits = (card >> 12) & 0xF;
            const suit_idx: usize = switch (suit_bits) {
                1 => 0, // Spades
                2 => 1, // Hearts
                4 => 2, // Diamonds
                8 => 3, // Clubs
                else => 0,
            };
            suits[suit_idx] += 1;
        }

        var flush_draw = false;
        for (suits) |count| {
            if (count == 4) flush_draw = true;
        }

        // Check for straight draws (simplified)
        var ranks = std.StaticBitSet(13).initEmpty();
        for (hole_cards) |card| {
            const rank = (card >> 8) & 0xF;
            ranks.set(rank);
        }
        for (board) |card| {
            const rank = (card >> 8) & 0xF;
            ranks.set(rank);
        }

        // Count consecutive ranks for straight potential
        var consecutive: u8 = 0;
        var max_consecutive: u8 = 0;
        for (0..13) |i| {
            if (ranks.isSet(i)) {
                consecutive += 1;
                if (consecutive > max_consecutive) {
                    max_consecutive = consecutive;
                }
            } else {
                consecutive = 0;
            }
        }

        const straight_draw = max_consecutive >= 4;

        // Return combined draw potential
        if (flush_draw and straight_draw) return 0.8;
        if (flush_draw) return 0.6;
        if (straight_draw) return 0.4;
        return 0.0;
    }

    fn calculateNutPotential(self: *Self, hole_cards: [2]hand_eval.Card, board: []const hand_eval.Card) !f64 {
        _ = self;
        _ = hole_cards;
        _ = board;

        // Simplified nut potential calculation
        // In a full implementation, this would check if we can make the best possible hand
        // For now, return a placeholder based on hand strength
        return 0.0; // TODO: Implement proper nut potential calculation
    }
};

/// K-means clustering implementation
pub const KMeans = struct {
    k: usize,
    max_iterations: u32,
    convergence_threshold: f64,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, k: usize) Self {
        return Self{
            .allocator = allocator,
            .k = k,
            .max_iterations = MAX_ITERATIONS,
            .convergence_threshold = CONVERGENCE_THRESHOLD,
        };
    }

    /// Cluster data points into k clusters
    pub fn cluster(
        self: *Self,
        data: []const HandFeatures,
    ) ![]usize {
        if (data.len < self.k) {
            return error.InsufficientData;
        }

        // Initialize cluster assignments
        var assignments = try self.allocator.alloc(usize, data.len);

        // Initialize centroids using k-means++ algorithm
        const centroids = try self.initializeCentroidsKMeansPlusPlus(data);
        defer self.allocator.free(centroids);

        var iteration: u32 = 0;
        var converged = false;

        while (iteration < self.max_iterations and !converged) {
            // Assignment step
            var changed: usize = 0;
            for (data, 0..) |point, i| {
                const new_cluster = self.findNearestCentroid(point, centroids);
                if (assignments[i] != new_cluster) {
                    changed += 1;
                    assignments[i] = new_cluster;
                }
            }

            // Update step
            try self.updateCentroids(centroids, data, assignments);

            // Check convergence
            const change_ratio = @as(f64, @floatFromInt(changed)) / @as(f64, @floatFromInt(data.len));
            converged = change_ratio < self.convergence_threshold;

            iteration += 1;
        }

        return assignments;
    }

    fn initializeCentroidsKMeansPlusPlus(self: *Self, data: []const HandFeatures) ![]HandFeatures {
        var centroids = try self.allocator.alloc(HandFeatures, self.k);
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();

        // Choose first centroid randomly
        const first_idx = random.intRangeAtMost(usize, 0, data.len - 1);
        centroids[0] = data[first_idx];

        // Choose remaining centroids with probability proportional to squared distance
        for (1..self.k) |i| {
            var distances = try self.allocator.alloc(f64, data.len);
            defer self.allocator.free(distances);

            var total_distance: f64 = 0.0;
            for (data, 0..) |point, j| {
                var min_dist: f64 = std.math.inf(f64);
                for (0..i) |c| {
                    const dist = point.distance(centroids[c]);
                    if (dist < min_dist) {
                        min_dist = dist;
                    }
                }
                distances[j] = min_dist * min_dist;
                total_distance += distances[j];
            }

            // Choose next centroid based on weighted probability
            const threshold = random.float(f64) * total_distance;
            var cumulative: f64 = 0.0;
            for (distances, 0..) |dist, j| {
                cumulative += dist;
                if (cumulative >= threshold) {
                    centroids[i] = data[j];
                    break;
                }
            }
        }

        return centroids;
    }

    fn findNearestCentroid(self: *Self, point: HandFeatures, centroids: []HandFeatures) usize {
        _ = self;

        var min_dist = std.math.inf(f64);
        var nearest: usize = 0;

        for (centroids, 0..) |centroid, i| {
            const dist = point.distance(centroid);
            if (dist < min_dist) {
                min_dist = dist;
                nearest = i;
            }
        }

        return nearest;
    }

    fn updateCentroids(
        self: *Self,
        centroids: []HandFeatures,
        data: []const HandFeatures,
        assignments: []const usize,
    ) !void {
        // Initialize counts
        var counts = try self.allocator.alloc(usize, self.k);
        defer self.allocator.free(counts);
        @memset(counts, 0);

        // Reset centroids
        for (centroids) |*centroid| {
            centroid.* = HandFeatures{
                .ehs = 0.0,
                .ehs2 = 0.0,
                .positive_potential = 0.0,
                .negative_potential = 0.0,
                .immediate_strength = 0.0,
                .draw_potential = 0.0,
                .nut_potential = 0.0,
            };
        }

        // Sum features for each cluster
        for (data, assignments) |point, cluster_id| {
            centroids[cluster_id].ehs += point.ehs;
            centroids[cluster_id].ehs2 += point.ehs2;
            centroids[cluster_id].positive_potential += point.positive_potential;
            centroids[cluster_id].negative_potential += point.negative_potential;
            centroids[cluster_id].immediate_strength += point.immediate_strength;
            centroids[cluster_id].draw_potential += point.draw_potential;
            centroids[cluster_id].nut_potential += point.nut_potential;
            counts[cluster_id] += 1;
        }

        // Average to get new centroids
        for (centroids, counts) |*centroid, count| {
            if (count > 0) {
                const n = @as(f64, @floatFromInt(count));
                centroid.ehs /= n;
                centroid.ehs2 /= n;
                centroid.positive_potential /= n;
                centroid.negative_potential /= n;
                centroid.immediate_strength /= n;
                centroid.draw_potential /= n;
                centroid.nut_potential /= n;
            }
        }
    }
};

/// Preflop hand clustering
pub const PreflopClusterer = struct {
    allocator: std.mem.Allocator,
    clusters: []u8, // 169 canonical hands -> cluster IDs

    const Self = @This();

    // Canonical hand indices (0-168)
    // Pairs: 0-12 (AA, KK, ..., 22)
    // Suited: 13-90 (AKs, AQs, ..., 32s)
    // Offsuit: 91-168 (AKo, AQo, ..., 32o)

    pub fn init(allocator: std.mem.Allocator) !Self {
        const clusters = try allocator.alloc(u8, PREFLOP_CANONICAL_HANDS);

        // Initialize with default clustering based on hand strength
        // This is a simplified version - in production, use actual equity calculations
        for (clusters, 0..) |*cluster, i| {
            if (i < 13) { // Pairs
                const pair_rank = 12 - i; // AA=12, KK=11, ..., 22=0
                if (pair_rank >= 10) cluster.* = 0 // Premium pairs (AA-QQ)
                else if (pair_rank >= 7) cluster.* = 1 // Good pairs (JJ-99)
                else if (pair_rank >= 4) cluster.* = 2 // Medium pairs (88-55)
                else cluster.* = 3; // Small pairs (44-22)
            } else if (i < 91) { // Suited hands
                const suited_idx = i - 13;
                if (suited_idx < 10) cluster.* = 0 // Premium suited (AKs-ATs)
                else if (suited_idx < 25) cluster.* = 1 // Good suited
                else if (suited_idx < 45) cluster.* = 2 // Medium suited
                else cluster.* = 3; // Weak suited
            } else { // Offsuit hands
                const offsuit_idx = i - 91;
                if (offsuit_idx < 5) cluster.* = 1 // Premium offsuit (AKo-AQo)
                else if (offsuit_idx < 15) cluster.* = 2 // Good offsuit
                else if (offsuit_idx < 35) cluster.* = 3 // Medium offsuit
                else cluster.* = 4; // Weak offsuit
            }
        }

        return Self{
            .allocator = allocator,
            .clusters = clusters,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.clusters);
    }

    pub fn getCanonicalIndex(c1: hand_eval.Card, c2: hand_eval.Card) usize {
        const r1 = (c1 >> 8) & 0xF;
        const r2 = (c2 >> 8) & 0xF;
        const s1 = (c1 >> 12) & 0xF;
        const s2 = (c2 >> 12) & 0xF;

        const suited = (s1 == s2);

        // Ensure r1 >= r2 for canonical form
        const high_rank = @max(r1, r2);
        const low_rank = @min(r1, r2);

        if (high_rank == low_rank) {
            // Pair
            return 12 - high_rank;
        } else if (suited) {
            // Suited non-pair
            const offset: usize = 13;
            var idx: usize = offset;

            // Calculate position in suited matrix
            var hr: usize = 12;
            while (hr > 0) : (hr -= 1) {
                var lr: usize = 0;
                while (lr < hr) : (lr += 1) {
                    if (hr == high_rank and lr == low_rank) {
                        return idx;
                    }
                    idx += 1;
                }
            }
            return idx;
        } else {
            // Offsuit non-pair
            const offset: usize = 91;
            var idx: usize = offset;

            // Calculate position in offsuit matrix
            var hr: usize = 12;
            while (hr > 0) : (hr -= 1) {
                var lr: usize = 0;
                while (lr < hr) : (lr += 1) {
                    if (hr == high_rank and lr == low_rank) {
                        return idx;
                    }
                    idx += 1;
                }
            }
            return idx;
        }
    }

    pub fn getCluster(self: *Self, c1: hand_eval.Card, c2: hand_eval.Card) u8 {
        const idx = getCanonicalIndex(c1, c2);
        return self.clusters[idx];
    }

    /// Train clusters using equity calculations
    pub fn trainWithEquity(
        self: *Self,
        evaluator: *hand_eval.HandEvaluator,
        n_clusters: usize,
        n_simulations: u32,
    ) !void {
        // Generate features for all canonical hands
        var features = try self.allocator.alloc(HandFeatures, PREFLOP_CANONICAL_HANDS);
        defer self.allocator.free(features);

        var extractor = FeatureExtractor.init(self.allocator, evaluator, n_simulations);

        // Calculate equity for each canonical hand
        for (0..PREFLOP_CANONICAL_HANDS) |i| {
            const hand = self.getHandFromCanonicalIndex(i);
            const board = [_]hand_eval.Card{}; // Empty board for preflop
            features[i] = try extractor.extractFeatures(hand, &board);
        }

        // Cluster using k-means
        var kmeans = KMeans.init(self.allocator, n_clusters);
        const assignments = try kmeans.cluster(features);
        defer self.allocator.free(assignments);

        // Update cluster assignments
        for (assignments, 0..) |cluster, i| {
            self.clusters[i] = @intCast(cluster);
        }
    }

    fn getHandFromCanonicalIndex(self: *Self, idx: usize) [2]hand_eval.Card {
        _ = self;

        // This is a simplified version - returns representative cards for each canonical hand
        if (idx < 13) {
            // Pairs
            const rank = @as(u32, @intCast(12 - idx));
            const c1 = hand_eval.CardOps.new(rank, hand_eval.SUIT_SPADES);
            const c2 = hand_eval.CardOps.new(rank, hand_eval.SUIT_HEARTS);
            return [2]hand_eval.Card{ c1, c2 };
        } else if (idx < 91) {
            // Suited
            const suited_idx = idx - 13;
            var count: usize = 0;
            var hr: u32 = 12;
            while (hr > 0) : (hr -= 1) {
                var lr: u32 = hr - 1;
                while (lr < hr) : (lr -= 1) {
                    if (lr == 0) break;
                    if (count == suited_idx) {
                        const c1 = hand_eval.CardOps.new(hr, hand_eval.SUIT_SPADES);
                        const c2 = hand_eval.CardOps.new(lr, hand_eval.SUIT_SPADES);
                        return [2]hand_eval.Card{ c1, c2 };
                    }
                    count += 1;
                }
                if (lr == 0 and count == suited_idx) {
                    const c1 = hand_eval.CardOps.new(hr, hand_eval.SUIT_SPADES);
                    const c2 = hand_eval.CardOps.new(0, hand_eval.SUIT_SPADES);
                    return [2]hand_eval.Card{ c1, c2 };
                }
            }
        } else {
            // Offsuit
            const offsuit_idx = idx - 91;
            var count: usize = 0;
            var hr: u32 = 12;
            while (hr > 0) : (hr -= 1) {
                var lr: u32 = hr - 1;
                while (lr < hr) : (lr -= 1) {
                    if (lr == 0) break;
                    if (count == offsuit_idx) {
                        const c1 = hand_eval.CardOps.new(hr, hand_eval.SUIT_SPADES);
                        const c2 = hand_eval.CardOps.new(lr, hand_eval.SUIT_HEARTS);
                        return [2]hand_eval.Card{ c1, c2 };
                    }
                    count += 1;
                }
                if (lr == 0 and count == offsuit_idx) {
                    const c1 = hand_eval.CardOps.new(hr, hand_eval.SUIT_SPADES);
                    const c2 = hand_eval.CardOps.new(0, hand_eval.SUIT_HEARTS);
                    return [2]hand_eval.Card{ c1, c2 };
                }
            }
        }

        // Fallback (should never reach here)
        const c1 = hand_eval.CardOps.fromString("As");
        const c2 = hand_eval.CardOps.fromString("Ks");
        return [2]hand_eval.Card{ c1, c2 };
    }
};

/// Postflop clustering with dynamic board textures
pub const PostflopClusterer = struct {
    allocator: std.mem.Allocator,
    evaluator: *hand_eval.HandEvaluator,
    flop_clusters: std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    turn_clusters: std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    river_clusters: std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, evaluator: *hand_eval.HandEvaluator) Self {
        return Self{
            .allocator = allocator,
            .evaluator = evaluator,
            .flop_clusters = std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .turn_clusters = std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .river_clusters = std.HashMap(u64, u16, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.flop_clusters.deinit();
        self.turn_clusters.deinit();
        self.river_clusters.deinit();
    }

    /// Get or compute cluster for a hand on a specific board
    pub fn getCluster(
        self: *Self,
        hole_cards: [2]hand_eval.Card,
        board: []const hand_eval.Card,
    ) !u16 {
        const key = self.computeKey(hole_cards, board);

        // Check if already computed
        const map = switch (board.len) {
            3 => &self.flop_clusters,
            4 => &self.turn_clusters,
            5 => &self.river_clusters,
            else => return error.InvalidBoardSize,
        };

        if (map.get(key)) |cluster| {
            return cluster;
        }

        // Compute features and assign to nearest cluster
        var extractor = FeatureExtractor.init(self.allocator, self.evaluator, DEFAULT_N_SIMULATIONS);
        const features = try extractor.extractFeatures(hole_cards, board);

        // For now, use a simple bucketing based on EHS
        // In production, use trained centroids
        const n_clusters: u16 = switch (board.len) {
            3 => DEFAULT_FLOP_CLUSTERS,
            4 => DEFAULT_TURN_CLUSTERS,
            5 => DEFAULT_RIVER_CLUSTERS,
            else => unreachable,
        };

        const cluster = @as(u16, @intFromFloat(features.ehs * @as(f64, @floatFromInt(n_clusters - 1))));
        try map.put(key, cluster);

        return cluster;
    }

    fn computeKey(self: *Self, hole_cards: [2]hand_eval.Card, board: []const hand_eval.Card) u64 {
        _ = self;

        var key: u64 = 0;

        // Pack hole cards into key
        key |= @as(u64, hole_cards[0]) << 32;
        key |= @as(u64, hole_cards[1]);

        // XOR with board cards for uniqueness
        for (board) |card| {
            key ^= @as(u64, card) << @intCast(card & 0x1F);
        }

        return key;
    }
};

/// Cluster data storage and persistence
pub const ClusterStorage = struct {
    allocator: std.mem.Allocator,
    preflop_clusters: []u8,
    flop_centroids: []HandFeatures,
    turn_centroids: []HandFeatures,
    river_centroids: []HandFeatures,

    const Self = @This();
    const MAGIC = "PKRCLUST";
    const VERSION = 1;

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .preflop_clusters = &[_]u8{},
            .flop_centroids = &[_]HandFeatures{},
            .turn_centroids = &[_]HandFeatures{},
            .river_centroids = &[_]HandFeatures{},
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.preflop_clusters.len > 0) self.allocator.free(self.preflop_clusters);
        if (self.flop_centroids.len > 0) self.allocator.free(self.flop_centroids);
        if (self.turn_centroids.len > 0) self.allocator.free(self.turn_centroids);
        if (self.river_centroids.len > 0) self.allocator.free(self.river_centroids);
    }

    pub fn save(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Use direct file I/O

        // Write header
        try file.writeAll(MAGIC);
        try io_helpers.writeInt(file, u32, VERSION);

        // Write preflop clusters
        try io_helpers.writeInt(file, u32, @intCast(self.preflop_clusters.len));
        try file.writeAll(self.preflop_clusters);

        // Write centroids
        try self.writeCentroids(file, self.flop_centroids);
        try self.writeCentroids(file, self.turn_centroids);
        try self.writeCentroids(file, self.river_centroids);
    }

    pub fn load(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Read and verify header
        var magic: [8]u8 = undefined;
        _ = try file.read(&magic);
        if (!std.mem.eql(u8, &magic, MAGIC)) {
            return error.InvalidFileFormat;
        }

        const version = try io_helpers.readInt(file, u32);
        if (version != VERSION) {
            return error.UnsupportedVersion;
        }

        // Read preflop clusters
        const preflop_len = try io_helpers.readInt(file, u32);
        // Free existing allocation before creating new one
        if (self.preflop_clusters.len > 0) {
            self.allocator.free(self.preflop_clusters);
        }
        self.preflop_clusters = try self.allocator.alloc(u8, preflop_len);
        _ = try file.read(self.preflop_clusters);

        // Read centroids (free existing allocations first)
        if (self.flop_centroids.len > 0) {
            self.allocator.free(self.flop_centroids);
        }
        self.flop_centroids = try self.readCentroids(file);
        
        if (self.turn_centroids.len > 0) {
            self.allocator.free(self.turn_centroids);
        }
        self.turn_centroids = try self.readCentroids(file);
        
        if (self.river_centroids.len > 0) {
            self.allocator.free(self.river_centroids);
        }
        self.river_centroids = try self.readCentroids(file);
    }

    fn writeCentroids(self: *Self, file: std.fs.File, centroids: []HandFeatures) !void {
        _ = self;

        try io_helpers.writeInt(file, u32, @intCast(centroids.len));
        for (centroids) |centroid| {
            try file.writeAll(std.mem.asBytes(&centroid));
        }
    }

    fn readCentroids(self: *Self, file: std.fs.File) ![]HandFeatures {
        const len = try io_helpers.readInt(file, u32);
        const centroids = try self.allocator.alloc(HandFeatures, len);

        for (centroids) |*centroid| {
            _ = try file.read(std.mem.asBytes(centroid));
        }

        return centroids;
    }
};

// Tests
test "preflop canonical index calculation" {
    const testing = std.testing;

    // Test pairs
    const aa_idx = PreflopClusterer.getCanonicalIndex(
        hand_eval.CardOps.fromString("As"),
        hand_eval.CardOps.fromString("Ah"),
    );
    try testing.expectEqual(@as(usize, 0), aa_idx);

    const kk_idx = PreflopClusterer.getCanonicalIndex(
        hand_eval.CardOps.fromString("Ks"),
        hand_eval.CardOps.fromString("Kh"),
    );
    try testing.expectEqual(@as(usize, 1), kk_idx);

    // Test suited hands
    const aks_idx = PreflopClusterer.getCanonicalIndex(
        hand_eval.CardOps.fromString("As"),
        hand_eval.CardOps.fromString("Ks"),
    );
    try testing.expect(aks_idx >= 13 and aks_idx < 91);

    // Test offsuit hands
    const ako_idx = PreflopClusterer.getCanonicalIndex(
        hand_eval.CardOps.fromString("As"),
        hand_eval.CardOps.fromString("Kh"),
    );
    try testing.expect(ako_idx >= 91 and ako_idx < 169);
}

test "hand features distance calculation" {
    const testing = std.testing;

    const f1 = HandFeatures{
        .ehs = 0.5,
        .ehs2 = 0.25,
        .positive_potential = 0.3,
        .negative_potential = 0.2,
        .immediate_strength = 0.6,
        .draw_potential = 0.1,
        .nut_potential = 0.05,
    };

    const f2 = HandFeatures{
        .ehs = 0.7,
        .ehs2 = 0.49,
        .positive_potential = 0.1,
        .negative_potential = 0.3,
        .immediate_strength = 0.8,
        .draw_potential = 0.0,
        .nut_potential = 0.1,
    };

    const dist = f1.distance(f2);
    try testing.expect(dist > 0.0);

    // Distance to self should be zero
    const self_dist = f1.distance(f1);
    try testing.expectApproxEqAbs(@as(f64, 0.0), self_dist, 0.0001);
}

test "k-means clustering basic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create sample data
    const data = [_]HandFeatures{
        .{ .ehs = 0.1, .ehs2 = 0.01, .positive_potential = 0.1, .negative_potential = 0.8, .immediate_strength = 0.1, .draw_potential = 0.0, .nut_potential = 0.0 },
        .{ .ehs = 0.2, .ehs2 = 0.04, .positive_potential = 0.2, .negative_potential = 0.7, .immediate_strength = 0.2, .draw_potential = 0.1, .nut_potential = 0.0 },
        .{ .ehs = 0.8, .ehs2 = 0.64, .positive_potential = 0.7, .negative_potential = 0.1, .immediate_strength = 0.8, .draw_potential = 0.0, .nut_potential = 0.5 },
        .{ .ehs = 0.9, .ehs2 = 0.81, .positive_potential = 0.8, .negative_potential = 0.05, .immediate_strength = 0.9, .draw_potential = 0.0, .nut_potential = 0.7 },
    };

    var kmeans = KMeans.init(allocator, 2);
    const assignments = try kmeans.cluster(&data);
    defer allocator.free(assignments);

    // Check that we have 2 clusters
    try testing.expectEqual(@as(usize, 4), assignments.len);

    // Weak hands should be in one cluster, strong in another
    try testing.expectEqual(assignments[0], assignments[1]); // Weak hands together
    try testing.expectEqual(assignments[2], assignments[3]); // Strong hands together
    try testing.expect(assignments[0] != assignments[2]); // Different clusters
}
