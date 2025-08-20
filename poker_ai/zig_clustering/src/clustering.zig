const std = @import("std");
const Card = @import("cards.zig").Card;
const Storage = @import("storage.zig").Storage;
const Distribution = @import("storage.zig").Distribution;

// K-means clustering implementation
pub const KMeans = struct {
    n_clusters: usize,
    centroids: [][]f32,
    allocator: std.mem.Allocator,
    batch_size: usize,
    n_features: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        n_clusters: usize,
        n_features: usize,
        batch_size: usize,
    ) !KMeans {
        // Allocate centroids first
        const centroids = try allocator.alloc([]f32, n_clusters);
        
        // Initialize each centroid with reproducible random values
        var prng = std.Random.DefaultPrng.init(123); // Fixed seed for K-means
        const random = prng.random();
        
        for (centroids) |*centroid| {
            centroid.* = try allocator.alloc(f32, n_features);
            for (centroid.*) |*val| {
                val.* = random.float(f32);
            }
        }
        
        return KMeans{
            .n_clusters = n_clusters,
            .centroids = centroids,
            .allocator = allocator,
            .batch_size = batch_size,
            .n_features = n_features,
        };
    }

    pub fn deinit(self: *KMeans) void {
        for (self.centroids) |centroid| {
            self.allocator.free(centroid);
        }
        self.allocator.free(self.centroids);
    }

    pub fn partialFit(self: *KMeans, batch: []const []const f32) !void {
        // Mini-batch K-means update
        var cluster_counts = try self.allocator.alloc(usize, self.n_clusters);
        defer self.allocator.free(cluster_counts);
        @memset(cluster_counts, 0);

        var new_centroids = try self.allocator.alloc([]f32, self.n_clusters);
        defer {
            for (new_centroids) |centroid| {
                self.allocator.free(centroid);
            }
            self.allocator.free(new_centroids);
        }

        for (new_centroids) |*centroid| {
            centroid.* = try self.allocator.alloc(f32, self.n_features);
            @memset(centroid.*, 0);
        }

        // Assign points to clusters and accumulate
        for (batch) |point| {
            const cluster = self.predict(point);
            cluster_counts[cluster] += 1;

            for (point, 0..) |val, i| {
                new_centroids[cluster][i] += val;
            }
        }

        // Update centroids with learning rate
        const learning_rate: f32 = 0.1;
        for (self.centroids, 0..) |*centroid, c| {
            if (cluster_counts[c] > 0) {
                const count_f = @as(f32, @floatFromInt(cluster_counts[c]));
                for (centroid.*, 0..) |*val, i| {
                    const new_val = new_centroids[c][i] / count_f;
                    val.* = val.* * (1.0 - learning_rate) + new_val * learning_rate;
                }
            }
        }
    }

    pub fn predict(self: *KMeans, point: []const f32) usize {
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

const PokerEvaluator = @import("poker_evaluator.zig").PokerEvaluator;

// Hand evaluation for EHS calculation
pub const HandEvaluator = struct {
    // Use proper poker hand evaluation
    pub fn getWinner(our_hand: []const Card, opp_hand: []const Card, board: []const Card) u8 {
        return PokerEvaluator.compareHands(our_hand, opp_hand, board);
    }
};

// EHS (Expected Hand Strength) calculator
pub fn calculateEHS(
    allocator: std.mem.Allocator,
    our_hand: []const Card,
    board: []const Card,
    available_cards: []const Card,
    n_simulations: usize,
) !f32 {
    _ = allocator; // Reserved for future use
    if (available_cards.len < 2) return 0.5;

    var wins: f32 = 0;
    var total: usize = 0;
    
    // Sample opponent hands
    const actual_sims = @min(n_simulations, available_cards.len * (available_cards.len - 1) / 2);
    
    // Use fixed seed for reproducibility (matching Python's approach)
    var prng = std.Random.DefaultPrng.init(42); // Fixed seed like Python's np.random.seed(42)
    const random = prng.random();

    var i: usize = 0;
    while (i < actual_sims) : (i += 1) {
        // Sample two cards for opponent
        const idx1 = random.intRangeLessThan(usize, 0, available_cards.len);
        var idx2 = random.intRangeLessThan(usize, 0, available_cards.len);
        while (idx2 == idx1) {
            idx2 = random.intRangeLessThan(usize, 0, available_cards.len);
        }

        const opp_hand = [_]Card{ available_cards[idx1], available_cards[idx2] };
        
        const winner = HandEvaluator.getWinner(our_hand, &opp_hand, board);
        if (winner == 0) {
            wins += 1;
        } else if (winner == 2) {
            wins += 0.5;
        }
        total += 1;
    }

    return if (total > 0) wins / @as(f32, @floatFromInt(total)) else 0.5;
}

// Stage processors
pub const RiverProcessor = struct {
    storage: *Storage,
    kmeans: KMeans,
    n_simulations: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        storage: *Storage,
        n_clusters: usize,
        n_simulations: usize,
    ) !RiverProcessor {
        return RiverProcessor{
            .storage = storage,
            .kmeans = try KMeans.init(allocator, n_clusters, 1, 50),
            .n_simulations = n_simulations,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RiverProcessor) void {
        self.kmeans.deinit();
    }

    pub fn processCombo(
        self: *RiverProcessor,
        combo_id: i64,
        combo: []const Card,
        all_cards: []const Card,
    ) !void {
        // River combo: 2 hand + 5 board
        const our_hand = combo[0..2];
        const board = combo[2..7];

        // Get available cards for opponent
        const available = try @import("cards.zig").getAvailableCards(
            self.allocator,
            all_cards,
            combo,
        );
        defer self.allocator.free(available);

        // Calculate EHS
        const ehs = try calculateEHS(
            self.allocator,
            our_hand,
            board,
            available,
            self.n_simulations,
        );

        // Store as distribution (single value for river)
        const dist = [_]f32{ehs};
        try self.storage.storeDistribution("river", combo_id, combo, &dist);

        // Update k-means
        const batch = [_][]const f32{&dist};
        try self.kmeans.partialFit(&batch);
    }
};

pub const TurnProcessor = struct {
    storage: *Storage,
    kmeans: KMeans,
    n_simulations: usize,
    n_river_clusters: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        storage: *Storage,
        n_clusters: usize,
        n_river_clusters: usize,
        n_simulations: usize,
    ) !TurnProcessor {
        return TurnProcessor{
            .storage = storage,
            .kmeans = try KMeans.init(allocator, n_clusters, n_river_clusters, 50),
            .n_simulations = n_simulations,
            .n_river_clusters = n_river_clusters,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TurnProcessor) void {
        self.kmeans.deinit();
    }

    pub fn processCombo(
        self: *TurnProcessor,
        combo_id: i64,
        combo: []const Card,
        all_cards: []const Card,
    ) !void {
        // Turn combo: 2 hand + 3 flop + 1 turn
        const our_hand = combo[0..2];
        const board = combo[2..6];

        // Get available cards for river
        const available = try @import("cards.zig").getAvailableCards(
            self.allocator,
            all_cards,
            combo,
        );
        defer self.allocator.free(available);

        // Create distribution over river outcomes
        var distribution = try self.allocator.alloc(f32, self.n_river_clusters);
        defer self.allocator.free(distribution);
        @memset(distribution, 0);

        // Sample river cards and calculate EHS distribution
        const n_samples = @min(self.n_simulations, available.len);
        // Use consistent seed for reproducibility
        var prng = std.Random.DefaultPrng.init(@intCast(42 + combo_id)); // Seed based on combo_id for variation
        const random = prng.random();

        var i: usize = 0;
        while (i < n_samples) : (i += 1) {
            // Sample river card
            const river_idx = random.intRangeLessThan(usize, 0, available.len);
            const river_card = available[river_idx];

            // Create full board
            var full_board = try self.allocator.alloc(Card, 5);
            defer self.allocator.free(full_board);
            @memcpy(full_board[0..4], board[0..4]);
            full_board[4] = river_card;

            // Calculate EHS for this river
            const river_available = try @import("cards.zig").getAvailableCards(
                self.allocator,
                all_cards,
                full_board,
            );
            defer self.allocator.free(river_available);

            const ehs = try calculateEHS(
                self.allocator,
                our_hand,
                full_board,
                river_available,
                10, // Fewer simulations for turn
            );

            // Map to cluster (simplified - would use actual river centroids in production)
            const cluster_idx = @min(
                @as(usize, @intFromFloat(ehs * @as(f32, @floatFromInt(self.n_river_clusters)))),
                self.n_river_clusters - 1,
            );
            distribution[cluster_idx] += 1.0 / @as(f32, @floatFromInt(n_samples));
        }

        // Store distribution
        try self.storage.storeDistribution("turn", combo_id, combo, distribution);

        // Update k-means
        const batch = [_][]const f32{distribution};
        try self.kmeans.partialFit(&batch);
    }
};