// Multi-threaded CFR training for improved performance
// Parallelized Monte Carlo CFR with thread-safe strategy updates

const std = @import("std");
const cfr = @import("cfr.zig");
const strategy_table = @import("strategy_table.zig");
const game_state = @import("game_state.zig");

// Thread-safe strategy table with proper synchronization
pub const ThreadSafeStrategyTable = struct {
    strategy_table: strategy_table.StrategyTable,
    mutex: std.Thread.Mutex,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .strategy_table = strategy_table.StrategyTable.init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.strategy_table.deinit();
    }
    
    pub fn getOrCreateStrategy(
        self: *Self,
        info_set_hash: u64,
        actions: []const game_state.Action,
    ) !*strategy_table.StrategyProfile {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Convert Actions to ActionTypes for strategy table
        var action_types = try self.strategy_table.allocator.alloc(game_state.ActionType, actions.len);
        defer self.strategy_table.allocator.free(action_types);
        for (actions, 0..) |action, i| {
            action_types[i] = action.action_type;
        }
        
        return self.strategy_table.getOrCreateStrategy(info_set_hash, action_types);
    }
    
    pub fn updateStrategy(
        self: *Self,
        info_set_hash: u64,
        action: game_state.Action,
        regret: f64,
        strategy: []const f64,
        weight: f64,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.strategy_table.updateStrategy(info_set_hash, action.action_type, regret, strategy, weight);
    }
    
    pub fn saveToFile(self: *Self, file_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.strategy_table.saveToFile(file_path);
    }
    
    pub fn loadFromFile(self: *Self, file_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.strategy_table.loadFromFile(file_path);
    }
};

// Work unit for parallel processing
const WorkUnit = struct {
    iteration_start: u32,
    iteration_count: u32,
    thread_id: u32,
};

// Thread worker data
const WorkerData = struct {
    work_unit: WorkUnit,
    shared_table: *ThreadSafeStrategyTable,
    config: cfr.CFRConfig,
    allocator: std.mem.Allocator,
    
    // Thread-local statistics (non-atomic, will be collected at the end)
    nodes_processed: u32,
    total_utility: f64,
};

// Parallel CFR trainer
pub const ParallelCFRTrainer = struct {
    config: cfr.CFRConfig,
    shared_strategy_table: ThreadSafeStrategyTable,
    num_threads: u32,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: cfr.CFRConfig, num_threads: u32) Self {
        return Self{
            .config = config,
            .shared_strategy_table = ThreadSafeStrategyTable.init(allocator),
            .num_threads = num_threads,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.shared_strategy_table.deinit();
    }
    
    // Run parallel CFR training
    pub fn train(self: *Self) !void {
        std.log.info("Starting parallel MCCFR training with {} threads", .{self.num_threads});
        
        // Create worker threads
        const threads = try self.allocator.alloc(std.Thread, self.num_threads);
        defer self.allocator.free(threads);
        
        var worker_data = try self.allocator.alloc(WorkerData, self.num_threads);
        defer self.allocator.free(worker_data);
        
        // Calculate work distribution
        const iterations_per_thread = self.config.iterations / self.num_threads;
        const remaining_iterations = self.config.iterations % self.num_threads;
        
        // Initialize worker data and spawn threads
        for (threads, 0..) |*thread, i| {
            const thread_iterations = iterations_per_thread + 
                (if (i < remaining_iterations) @as(u32, 1) else 0);
            
            worker_data[i] = WorkerData{
                .work_unit = WorkUnit{
                    .iteration_start = @intCast(i * iterations_per_thread),
                    .iteration_count = thread_iterations,
                    .thread_id = @intCast(i),
                },
                .shared_table = &self.shared_strategy_table,
                .config = self.config,
                .allocator = self.allocator,
                .nodes_processed = 0,
                .total_utility = 0.0,
            };
            
            thread.* = try std.Thread.spawn(.{}, workerFunction, .{&worker_data[i]});
        }
        
        // Wait for all threads to complete
        for (threads) |*thread| {
            thread.join();
        }
        
        // Collect statistics
        var total_nodes: u32 = 0;
        var total_utility: f64 = 0.0;
        
        for (worker_data) |*data| {
            total_nodes += data.nodes_processed;
            total_utility += data.total_utility;
        }
        
        std.log.info("Parallel MCCFR training completed: {} nodes processed, avg utility: {d:.6}", 
                    .{ total_nodes, total_utility / @as(f64, @floatFromInt(self.config.iterations)) });
    }
    
    // Save trained strategy to file
    pub fn saveStrategy(self: *Self, file_path: []const u8) !void {
        try self.shared_strategy_table.saveToFile(file_path);
    }
    
    // Load pre-trained strategy from file
    pub fn loadStrategy(self: *Self, file_path: []const u8) !void {
        try self.shared_strategy_table.loadFromFile(file_path);
    }
    
    // Get strategy table for external use
    pub fn getStrategyTable(self: *Self) *ThreadSafeStrategyTable {
        return &self.shared_strategy_table;
    }
};

// Worker thread function
fn workerFunction(worker_data: *WorkerData) void {
    // Create thread-local CFR trainer components
    // TODO: AbstractionTable not yet implemented
    // var local_abstraction_table = lookup_tables.AbstractionTable.init(worker_data.allocator) catch {
    //     std.log.err("Failed to initialize abstraction table in worker thread {}", .{worker_data.work_unit.thread_id});
    //     return;
    // };
    // defer local_abstraction_table.deinit();
    
    var local_hand_evaluator = hand_eval.HandEvaluator.init();
    // HandEvaluator has no deinit
    
    // Thread-local RNG
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp() + worker_data.work_unit.thread_id));
    
    // Process assigned iterations
    for (0..worker_data.work_unit.iteration_count) |local_iteration| {
        const global_iteration = worker_data.work_unit.iteration_start + @as(u32, @intCast(local_iteration));
        
        // Create random game scenario
        var game = createRandomGameLocal(worker_data.allocator, &rng) catch {
            std.log.err("Failed to create random game in worker thread {}", .{worker_data.work_unit.thread_id});
            continue;
        };
        defer game.deinit();
        
        // Run CFR for each player
        for (0..game.num_players) |player_id| {
            const utility = runCFRLocal(
                &game,
                @intCast(player_id),
                1.0,
                1.0,
                worker_data.shared_table,
                &local_hand_evaluator,
                worker_data.allocator,
                &rng,
            ) catch {
                std.log.err("CFR failed in worker thread {}", .{worker_data.work_unit.thread_id});
                continue;
            };
            
            // Update statistics (thread-local, no atomics needed)
            worker_data.nodes_processed += 1;
            worker_data.total_utility += utility;
        }
        
        // Periodic progress reporting
        if (global_iteration % 1000 == 0) {
            std.log.debug("Thread {} completed iteration {}", .{ worker_data.work_unit.thread_id, global_iteration });
        }
    }
    
    std.log.info("Worker thread {} completed {} iterations", 
                .{ worker_data.work_unit.thread_id, worker_data.work_unit.iteration_count });
}

// Thread-local CFR implementation
fn runCFRLocal(
    game_state_ptr: *game_state.GameState,
    player: u8,
    p0: f64,
    p1: f64,
    shared_table: *ThreadSafeStrategyTable,
    hand_evaluator: *hand_eval.HandEvaluator,
    allocator: std.mem.Allocator,
    rng: *std.Random.DefaultPrng,
) !f64 {
    // hand_evaluator will be used for terminal evaluation in full implementation
    
    if (game_state_ptr.isTerminal()) {
        return getUtilityLocal(game_state_ptr, player);
    }
    
    const current_player = game_state_ptr.current_player;
    
    // Get information set
    const info_set_data = try game_state_ptr.getInfoSet(current_player);
    defer allocator.free(info_set_data);
    
    const info_set_hash = std.hash_map.hashString(info_set_data);
    
    // Get available actions
    const actions = try getAvailableActionsLocal(game_state_ptr, allocator);
    defer allocator.free(actions);
    
    // Get or create strategy profile
    const strategy_profile = try shared_table.getOrCreateStrategy(info_set_hash, actions);
    
    // Calculate current strategy from regrets
    strategy_profile.computeCurrentStrategy();
    
    var utilities = try allocator.alloc(f64, actions.len);
    defer allocator.free(utilities);
    
    var node_utility: f64 = 0.0;
    
    // Sample action based on strategy or use deterministic exploration
    const sample_action_index = if (rng.random().float(f64) < 0.05) 
        rng.random().uintLessThan(usize, actions.len) // 5% random exploration
    else blk: {
        const sampled_action = strategy_profile.action_probs.sampleAction(rng.random());
        // Find the index of this action in our actions array
        for (actions, 0..) |action, idx| {
            if (action.action_type == sampled_action) {
                break :blk idx;
            }
        }
        break :blk 0; // Default to first action if not found
    };
    
    for (actions, 0..) |action, i| {
        var new_game = try cloneGameStateLocal(game_state_ptr, allocator);
        defer new_game.deinit();
        
        _ = try new_game.applyAction(action);
        
        if (new_game.isBettingComplete()) {
            new_game.nextRound();
        }
        
        const prob = strategy_profile.action_probs.probabilities[i];
        const new_p0 = if (current_player == 0) p0 * prob else p0;
        const new_p1 = if (current_player == 1) p1 * prob else p1;
        
        // Use importance sampling for better convergence
        if (i == sample_action_index) {
            utilities[i] = try runCFRLocal(&new_game, player, new_p0, new_p1, shared_table, hand_evaluator, allocator, rng);
            utilities[i] /= prob; // Importance sampling correction
        } else {
            utilities[i] = 0.0; // Don't traverse this branch
        }
        
        node_utility += prob * utilities[i];
    }
    
    // Update regrets for acting player
    if (current_player == player) {
        const counterfactual_prob = if (player == 0) p1 else p0;
        
        for (actions, 0..) |action, i| {
            const regret = utilities[i] - node_utility;
            try shared_table.updateStrategy(
                info_set_hash,
                action,
                counterfactual_prob * regret,
                strategy_profile.action_probs.probabilities,
                counterfactual_prob,
            );
        }
    }
    
    return node_utility;
}

// Helper functions
fn createRandomGameLocal(allocator: std.mem.Allocator, rng: *std.Random.DefaultPrng) !game_state.GameState {
    var game = try game_state.GameState.init(allocator, 2, 5, 10);
    
    // Create and shuffle deck
    var deck = std.ArrayList(u8).init(allocator);
    defer deck.deinit();
    
    for (0..52) |i| {
        try deck.append(@intCast(i));
    }
    
    rng.random().shuffle(u8, deck.items);
    
    // Deal hole cards
    var hands = [2][2]u8{
        .{ deck.items[0], deck.items[1] },
        .{ deck.items[2], deck.items[3] },
    };
    
    game.dealHoleCards(&hands);
    
    return game;
}

fn cloneGameStateLocal(original: *game_state.GameState, allocator: std.mem.Allocator) !game_state.GameState {
    var clone = try game_state.GameState.init(
        allocator,
        original.num_players,
        original.small_blind,
        original.big_blind,
    );
    
    // Copy all game state
    clone.players = original.players;
    clone.active_players = original.active_players;
    clone.round = original.round;
    clone.board = original.board;
    clone.board_size = original.board_size;
    clone.current_player = original.current_player;
    clone.dealer_button = original.dealer_button;
    clone.pot = original.pot;
    clone.current_bet = original.current_bet;
    clone.last_raiser = original.last_raiser;
    
    // Copy action history
    for (original.actions.items) |action| {
        try clone.actions.append(action);
    }
    for (original.action_sequence.items) |action| {
        try clone.action_sequence.append(action);
    }
    
    return clone;
}

fn getAvailableActionsLocal(game_state_ptr: *game_state.GameState, allocator: std.mem.Allocator) ![]game_state.Action {
    var actions = std.ArrayList(game_state.Action).init(allocator);
    
    const current_bet = game_state_ptr.current_bet;
    const player = &game_state_ptr.players[game_state_ptr.current_player];
    
    // Always allow fold
    try actions.append(game_state.Action.fold());
    
    // Check or call
    if (current_bet == player.bet_this_round) {
        try actions.append(game_state.Action.check());
    } else {
        try actions.append(game_state.Action.call());
    }
    
    // Raise if possible
    const min_raise = current_bet + game_state_ptr.big_blind;
    if (min_raise <= player.stack + player.bet_this_round) {
        try actions.append(game_state.Action.raise(min_raise));
    }
    
    return actions.toOwnedSlice();
}

fn getUtilityLocal(game_state_ptr: *game_state.GameState, player: u8) f64 {
    if (game_state_ptr.active_players == 1) {
        return if (game_state_ptr.players[player].is_active) 
            @floatFromInt(game_state_ptr.pot) else 
            -@as(f64, @floatFromInt(game_state_ptr.players[player].total_bet));
    }
    
    // Simplified showdown evaluation
    return 0.0;
}

// Add missing imports at the top
const lookup_tables = @import("lookup_tables.zig");
const hand_eval = @import("hand_eval.zig");

test "thread safe strategy table" {
    const testing = std.testing;
    
    var table = ThreadSafeStrategyTable.init(testing.allocator);
    defer table.deinit();
    
    const actions = [_]game_state.Action{ game_state.Action.fold(), game_state.Action.call() };
    const strategy = try table.getOrCreateStrategy(12345, &actions);
    
    try testing.expectEqual(@as(u64, 12345), strategy.info_set_hash);
}

test "parallel cfr trainer initialization" {
    const testing = std.testing;
    
    const config = cfr.CFRConfig.default();
    var trainer = ParallelCFRTrainer.init(testing.allocator, config, 2);
    defer trainer.deinit();
    
    try testing.expectEqual(@as(u32, 2), trainer.num_threads);
}