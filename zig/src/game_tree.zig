//! Efficient Game Tree Representation for MCCFR
//! Provides cache-efficient tree traversal with work-stealing support

const std = @import("std");
const io_helpers = @import("io_helpers.zig");const game_state = @import("game_state.zig");
const GameState = game_state.GameState;
const Action = game_state.Action;
const Round = game_state.Round;

/// Compact node representation for game tree
pub const GameNode = packed struct {
    /// Hash of the game state (information set)
    state_hash: u64,
    
    /// Player to act at this node
    player: u8,
    
    /// Current betting round
    round: Round,
    
    /// Pot size at this node
    pot: u32,
    
    /// Number of active players
    active_players: u8,
    
    /// Index to first child in edge array
    first_child_idx: u32,
    
    /// Number of children (actions)
    num_children: u8,
    
    /// Whether this is a terminal node
    is_terminal: bool,
    
    /// Depth in the tree (for limiting search)
    depth: u8,
    
    /// Cached utility values for each player (if terminal)
    utilities: ?[6]f32,
};

/// Edge connecting nodes with actions
pub const ActionEdge = struct {
    /// The action taken to reach child
    action: Action,
    
    /// Index of child node
    child_idx: u32,
    
    /// Probability of taking this action (from strategy)
    probability: f32,
    
    /// Cumulative regret for this action
    regret: f32,
    
    /// Strategy sum for averaging
    strategy_sum: f32,
};

/// Work item for parallel processing
pub const WorkItem = struct {
    node_idx: u32,
    reach_prob: f32,
    player: u8,
};

/// Work-stealing queue for parallel traversal
pub const WorkQueue = struct {
    items: std.ArrayList(WorkItem),
    mutex: std.Thread.Mutex,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .items = std.ArrayList(WorkItem).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }
    
    pub fn push(self: *Self, item: WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.items.append(self.allocator, item);
    }
    
    pub fn trySteal(self: *Self) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.items.items.len > 0) {
            // Steal from the back for better cache locality
            return self.items.pop();
        }
        return null;
    }
    
    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.items.items.len;
    }
};

/// Visitor interface for tree traversal
pub const Visitor = struct {
    ptr: *anyopaque,
    visitFn: *const fn (ptr: *anyopaque, node: *GameNode, parent_action: ?Action) anyerror!void,
    
    pub fn visit(self: *Visitor, node: *GameNode, parent_action: ?Action) !void {
        return self.visitFn(self.ptr, node, parent_action);
    }
};

/// Efficient game tree with memory-mapped storage
pub const GameTree = struct {
    /// Packed array of nodes for cache efficiency
    nodes: std.ArrayList(GameNode),
    
    /// Edge array for actions
    edges: std.ArrayList(ActionEdge),
    
    /// Root node index
    root_idx: u32,
    
    /// Memory allocator
    allocator: std.mem.Allocator,
    
    /// Optional memory-mapped region for large trees
    mmap_region: ?[]align(std.mem.page_size) u8,
    
    /// Statistics
    stats: TreeStats,
    
    const Self = @This();
    
    pub const TreeStats = struct {
        total_nodes: u64,
        terminal_nodes: u64,
        max_depth: u32,
        total_edges: u64,
        memory_usage: usize,
    };
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .nodes = std.ArrayList(GameNode).init(allocator),
            .edges = std.ArrayList(ActionEdge).init(allocator),
            .root_idx = 0,
            .allocator = allocator,
            .mmap_region = null,
            .stats = TreeStats{
                .total_nodes = 0,
                .terminal_nodes = 0,
                .max_depth = 0,
                .total_edges = 0,
                .memory_usage = 0,
            },
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.nodes.deinit();
        self.edges.deinit();
        
        if (self.mmap_region) |region| {
            std.posix.munmap(region);
        }
    }
    
    /// Build game tree from initial state
    pub fn buildFromState(self: *Self, initial_state: *GameState, max_depth: u32) !void {
        // Clear existing tree
        self.nodes.clearRetainingCapacity();
        self.edges.clearRetainingCapacity();
        
        // Create root node
        const root_node = try self.createNode(initial_state, 0);
        self.root_idx = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, root_node);
        
        // Build tree recursively with depth limit
        try self.expandNode(self.root_idx, initial_state, max_depth);
        
        // Update statistics
        self.updateStats();
    }
    
    /// Create a node from game state
    fn createNode(self: *Self, state: *GameState, depth: u8) !GameNode {
        _ = self;
        
        var node = GameNode{
            .state_hash = try state.getInfoSetKey(state.current_player),
            .player = state.current_player,
            .round = state.round,
            .pot = state.pot,
            .active_players = state.active_players,
            .first_child_idx = 0,
            .num_children = 0,
            .is_terminal = state.isTerminal(),
            .depth = depth,
            .utilities = null,
        };
        
        // Cache utilities if terminal
        if (node.is_terminal) {
            var utils: [6]f32 = undefined;
            for (0..state.num_players) |p| {
                utils[p] = state.getUtility(@intCast(p));
            }
            node.utilities = utils;
        }
        
        return node;
    }
    
    /// Expand a node by generating children
    fn expandNode(self: *Self, node_idx: u32, state: *GameState, max_depth: u32) !void {
        const node = &self.nodes.items[node_idx];
        
        // Don't expand terminal nodes or beyond max depth
        if (node.is_terminal or node.depth >= max_depth) {
            return;
        }
        
        const actions = state.getLegalActions();
        node.first_child_idx = @intCast(self.edges.items.len);
        node.num_children = @intCast(actions.len);
        
        // Create edges and child nodes
        for (actions) |action| {
            // Clone state and apply action
            var next_state = try state.clone();
            defer next_state.deinit();
            try next_state.applyAction(action);
            
            // Create child node
            const child_node = try self.createNode(&next_state, node.depth + 1);
            const child_idx = @as(u32, @intCast(self.nodes.items.len));
            try self.nodes.append(self.allocator, child_node);
            
            // Create edge
            const edge = ActionEdge{
                .action = action,
                .child_idx = child_idx,
                .probability = 1.0 / @as(f32, @floatFromInt(actions.len)), // Initialize uniform
                .regret = 0.0,
                .strategy_sum = 0.0,
            };
            try self.edges.append(self.allocator, edge);
            
            // Recursively expand child
            try self.expandNode(child_idx, &next_state, max_depth);
        }
    }
    
    /// Traverse tree with visitor pattern
    pub fn traverse(self: *Self, visitor: *Visitor) !void {
        try self.traverseNode(self.root_idx, visitor, null);
    }
    
    fn traverseNode(self: *Self, node_idx: u32, visitor: *Visitor, parent_action: ?Action) !void {
        const node = &self.nodes.items[node_idx];
        
        // Visit current node
        try visitor.visit(node, parent_action);
        
        // Visit children if not terminal
        if (!node.is_terminal) {
            const first_edge = node.first_child_idx;
            const last_edge = first_edge + node.num_children;
            
            for (self.edges.items[first_edge..last_edge]) |edge| {
                try self.traverseNode(edge.child_idx, visitor, edge.action);
            }
        }
    }
    
    /// Parallel traversal with work stealing
    pub fn parallelTraverse(self: *Self, visitor: *Visitor, num_threads: u32) !void {
        var thread_pool = try std.ArrayList(std.Thread).initCapacity(self.allocator, 0);
        defer thread_pool.deinit();
        
        // Create work queues
        var work_queues = try self.allocator.alloc(WorkQueue, num_threads);
        defer self.allocator.free(work_queues);
        
        for (work_queues) |*queue| {
            queue.* = WorkQueue.init(self.allocator);
        }
        defer {
            for (work_queues) |*queue| {
                queue.deinit();
            }
        }
        
        // Initialize with root
        try work_queues[0].push(WorkItem{
            .node_idx = self.root_idx,
            .reach_prob = 1.0,
            .player = 0,
        });
        
        // Launch worker threads
        for (0..num_threads) |tid| {
            const thread = try std.Thread.spawn(.{}, workerThread, .{
                self,
                visitor,
                &work_queues[tid],
                work_queues,
            });
            try thread_pool.append(self.allocator, thread);
        }
        
        // Wait for completion
        for (thread_pool.items) |thread| {
            thread.join();
        }
    }
    
    fn workerThread(
        tree: *Self,
        visitor: *Visitor,
        local_queue: *WorkQueue,
        all_queues: []WorkQueue,
    ) !void {
        while (true) {
            // Try local queue first
            if (local_queue.trySteal()) |work| {
                try tree.processWork(work, visitor, local_queue);
                continue;
            }
            
            // Try stealing from others
            var found = false;
            for (all_queues) |*queue| {
                if (queue.trySteal()) |work| {
                    try tree.processWork(work, visitor, local_queue);
                    found = true;
                    break;
                }
            }
            
            if (!found) {
                // Check if all queues are empty
                var all_empty = true;
                for (all_queues) |*queue| {
                    if (queue.size() > 0) {
                        all_empty = false;
                        break;
                    }
                }
                
                if (all_empty) {
                    break; // All work completed
                }
                
                // Brief sleep to avoid busy waiting
                std.Thread.sleep(1000); // 1 microsecond
            }
        }
    }
    
    fn processWork(self: *Self, work: WorkItem, visitor: *Visitor, queue: *WorkQueue) !void {
        const node = &self.nodes.items[work.node_idx];
        
        // Visit node
        try visitor.visit(node, null);
        
        // Add children to work queue
        if (!node.is_terminal) {
            const first_edge = node.first_child_idx;
            const last_edge = first_edge + node.num_children;
            
            for (self.edges.items[first_edge..last_edge]) |edge| {
                try queue.push(WorkItem{
                    .node_idx = edge.child_idx,
                    .reach_prob = work.reach_prob * edge.probability,
                    .player = work.player,
                });
            }
        }
    }
    
    /// Get node by index
    pub fn getNode(self: *Self, idx: u32) *GameNode {
        return &self.nodes.items[idx];
    }
    
    /// Get edges for a node
    pub fn getEdges(self: *Self, node: *GameNode) []ActionEdge {
        if (node.is_terminal) {
            return &[_]ActionEdge{};
        }
        
        const first = node.first_child_idx;
        const last = first + node.num_children;
        return self.edges.items[first..last];
    }
    
    /// Update tree statistics
    fn updateStats(self: *Self) void {
        self.stats.total_nodes = self.nodes.items.len;
        self.stats.total_edges = self.edges.items.len;
        
        var terminal_count: u64 = 0;
        var max_depth: u32 = 0;
        
        for (self.nodes.items) |node| {
            if (node.is_terminal) {
                terminal_count += 1;
            }
            max_depth = @max(max_depth, node.depth);
        }
        
        self.stats.terminal_nodes = terminal_count;
        self.stats.max_depth = max_depth;
        self.stats.memory_usage = 
            self.nodes.items.len * @sizeOf(GameNode) +
            self.edges.items.len * @sizeOf(ActionEdge);
    }
    
    /// Save tree to disk for persistence
    pub fn save(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        
        // Use direct file I/O
        
        // Write header
        try file.writeAll("GAMETREE");
        try io_helpers.writeInt(file, u32, 1); // Version
        
        // Write statistics
        try file.writeAll(std.mem.asBytes(&self.stats));
        
        // Write nodes
        try io_helpers.writeInt(file, u32, @intCast(self.nodes.items.len));
        for (self.nodes.items) |node| {
            try file.writeAll(std.mem.asBytes(&node));
        }
        
        // Write edges
        try io_helpers.writeInt(file, u32, @intCast(self.edges.items.len));
        for (self.edges.items) |edge| {
            try file.writeAll(std.mem.asBytes(&edge));
        }
        
        try io_helpers.writeInt(file, u32, self.root_idx);
    }
    
    /// Load tree from disk
    pub fn load(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        // Read and verify header
        var magic: [8]u8 = undefined;
        _ = try file.read(&magic);
        if (!std.mem.eql(u8, &magic, "GAMETREE")) {
            return error.InvalidFileFormat;
        }
        
        const version = try io_helpers.readInt(file, u32);
        if (version != 1) {
            return error.UnsupportedVersion;
        }
        
        // Read statistics
        _ = try file.read(std.mem.asBytes(&self.stats));
        
        // Read nodes
        const num_nodes = try io_helpers.readInt(file, u32);
        try self.nodes.ensureTotalCapacity(num_nodes);
        
        for (0..num_nodes) |_| {
            var node: GameNode = undefined;
            _ = try file.read(std.mem.asBytes(&node));
            try self.nodes.append(self.allocator, node);
        }
        
        // Read edges
        const num_edges = try io_helpers.readInt(file, u32);
        try self.edges.ensureTotalCapacity(num_edges);
        
        for (0..num_edges) |_| {
            var edge: ActionEdge = undefined;
            _ = try file.read(std.mem.asBytes(&edge));
            try self.edges.append(self.allocator, edge);
        }
        
        self.root_idx = try io_helpers.readInt(file, u32);
    }
};

test "Game tree construction" {
    const allocator = std.testing.allocator;
    
    var tree = try GameTree.init(allocator);
    defer tree.deinit();
    
    // Create a simple game state
    var state = try GameState.init(allocator, 2, 5, 10);
    defer state.deinit();
    
    // Build tree with max depth 2
    try tree.buildFromState(&state, 2);
    
    // Check tree was built
    try std.testing.expect(tree.nodes.items.len > 0);
    try std.testing.expect(tree.stats.max_depth <= 2);
}

test "Work queue operations" {
    const allocator = std.testing.allocator;
    
    var queue = WorkQueue.init(allocator);
    defer queue.deinit();
    
    // Push items
    try queue.push(WorkItem{ .node_idx = 1, .reach_prob = 1.0, .player = 0 });
    try queue.push(WorkItem{ .node_idx = 2, .reach_prob = 0.5, .player = 1 });
    
    // Steal items
    const item1 = queue.trySteal();
    try std.testing.expect(item1 != null);
    try std.testing.expect(item1.?.node_idx == 2); // LIFO
    
    const item2 = queue.trySteal();
    try std.testing.expect(item2 != null);
    try std.testing.expect(item2.?.node_idx == 1);
    
    const item3 = queue.trySteal();
    try std.testing.expect(item3 == null); // Empty
}