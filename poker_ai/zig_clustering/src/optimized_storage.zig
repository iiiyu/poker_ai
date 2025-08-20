const std = @import("std");
const sqlite = @import("sqlite");
const Card = @import("eval_card.zig").Card;

// Optimized storage with prepared statements and batching
pub const OptimizedStorage = struct {
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    
    // Prepared statements for maximum performance
    river_insert_stmt: *sqlite.Stmt,
    turn_insert_stmt: *sqlite.Stmt,
    flop_insert_stmt: *sqlite.Stmt,
    update_cluster_stmt: *sqlite.Stmt,
    
    // Write-ahead log for batching
    write_buffer: WriteBuffer,
    
    // Statistics
    total_writes: std.atomic.Value(usize),
    total_flushes: std.atomic.Value(usize),
    
    const WriteBuffer = struct {
        river_batch: std.ArrayList(RiverEntry),
        turn_batch: std.ArrayList(TurnEntry),
        flop_batch: std.ArrayList(FlopEntry),
        mutex: std.Thread.Mutex,
        max_size: usize,
        
        const RiverEntry = struct {
            combo_id: i32,
            hand_cards: [2]Card,
            board_cards: [5]Card,
            ehs_value: f32,
            cluster_id: ?i32,
        };
        
        const TurnEntry = struct {
            combo_id: i32,
            hand_cards: [2]Card,
            board_cards: [4]Card,
            distribution: []f32,
            cluster_id: ?i32,
        };
        
        const FlopEntry = struct {
            combo_id: i32,
            hand_cards: [2]Card,
            board_cards: [3]Card,
            distribution: []f32,
            cluster_id: ?i32,
        };
        
        fn init(allocator: std.mem.Allocator, max_size: usize) WriteBuffer {
            return WriteBuffer{
                .river_batch = std.ArrayList(RiverEntry).init(allocator),
                .turn_batch = std.ArrayList(TurnEntry).init(allocator),
                .flop_batch = std.ArrayList(FlopEntry).init(allocator),
                .mutex = .{},
                .max_size = max_size,
            };
        }
        
        fn deinit(self: *WriteBuffer) void {
            for (self.turn_batch.items) |entry| {
                self.turn_batch.allocator.free(entry.distribution);
            }
            for (self.flop_batch.items) |entry| {
                self.flop_batch.allocator.free(entry.distribution);
            }
            self.river_batch.deinit();
            self.turn_batch.deinit();
            self.flop_batch.deinit();
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8, batch_size: usize) !OptimizedStorage {
        // Open database with optimizations
        const db = try sqlite.Db.init(.{
            .mode = sqlite.Db.Mode{ .File = db_path },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .MultiThread,
        });
        
        // Set performance pragmas
        try db.exec("PRAGMA journal_mode = WAL", .{}, .{});
        try db.exec("PRAGMA synchronous = NORMAL", .{}, .{});
        try db.exec("PRAGMA cache_size = -262144", .{}, .{}); // 256MB
        try db.exec("PRAGMA temp_store = MEMORY", .{}, .{});
        try db.exec("PRAGMA mmap_size = 536870912", .{}, .{}); // 512MB
        try db.exec("PRAGMA page_size = 4096", .{}, .{});
        try db.exec("PRAGMA wal_autocheckpoint = 10000", .{}, .{});
        
        // Create tables with optimized schema
        try createOptimizedTables(db);
        
        // Prepare statements
        const river_insert_stmt = try db.prepare(
            \\ INSERT INTO river_clusters (combo_id, hand_card1_rank, hand_card1_suit,
            \\   hand_card2_rank, hand_card2_suit, board_card1_rank, board_card1_suit,
            \\   board_card2_rank, board_card2_suit, board_card3_rank, board_card3_suit,
            \\   board_card4_rank, board_card4_suit, board_card5_rank, board_card5_suit,
            \\   ehs_value, cluster_id)
            \\ VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        );
        
        const turn_insert_stmt = try db.prepare(
            \\ INSERT INTO turn_clusters (combo_id, hand_card1_rank, hand_card1_suit,
            \\   hand_card2_rank, hand_card2_suit, board_card1_rank, board_card1_suit,
            \\   board_card2_rank, board_card2_suit, board_card3_rank, board_card3_suit,
            \\   board_card4_rank, board_card4_suit, distribution, cluster_id)
            \\ VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        );
        
        const flop_insert_stmt = try db.prepare(
            \\ INSERT INTO flop_clusters (combo_id, hand_card1_rank, hand_card1_suit,
            \\   hand_card2_rank, hand_card2_suit, board_card1_rank, board_card1_suit,
            \\   board_card2_rank, board_card2_suit, board_card3_rank, board_card3_suit,
            \\   distribution, cluster_id)
            \\ VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        );
        
        const update_cluster_stmt = try db.prepare(
            \\ UPDATE ? SET cluster_id = ? WHERE combo_id = ?
        );
        
        return OptimizedStorage{
            .allocator = allocator,
            .db = db,
            .river_insert_stmt = river_insert_stmt,
            .turn_insert_stmt = turn_insert_stmt,
            .flop_insert_stmt = flop_insert_stmt,
            .update_cluster_stmt = update_cluster_stmt,
            .write_buffer = WriteBuffer.init(allocator, batch_size),
            .total_writes = std.atomic.Value(usize).init(0),
            .total_flushes = std.atomic.Value(usize).init(0),
        };
    }
    
    pub fn deinit(self: *OptimizedStorage) void {
        // Flush any remaining data
        self.flush() catch {};
        
        // Clean up statements
        self.river_insert_stmt.deinit();
        self.turn_insert_stmt.deinit();
        self.flop_insert_stmt.deinit();
        self.update_cluster_stmt.deinit();
        
        // Clean up buffer
        self.write_buffer.deinit();
        
        // Close database
        self.db.deinit();
    }
    
    fn createOptimizedTables(db: *sqlite.Db) !void {
        // River table with optimized indexes
        try db.exec(
            \\ CREATE TABLE IF NOT EXISTS river_clusters (
            \\   combo_id INTEGER PRIMARY KEY,
            \\   hand_card1_rank INTEGER NOT NULL,
            \\   hand_card1_suit TEXT NOT NULL,
            \\   hand_card2_rank INTEGER NOT NULL,
            \\   hand_card2_suit TEXT NOT NULL,
            \\   board_card1_rank INTEGER NOT NULL,
            \\   board_card1_suit TEXT NOT NULL,
            \\   board_card2_rank INTEGER NOT NULL,
            \\   board_card2_suit TEXT NOT NULL,
            \\   board_card3_rank INTEGER NOT NULL,
            \\   board_card3_suit TEXT NOT NULL,
            \\   board_card4_rank INTEGER NOT NULL,
            \\   board_card4_suit TEXT NOT NULL,
            \\   board_card5_rank INTEGER NOT NULL,
            \\   board_card5_suit TEXT NOT NULL,
            \\   ehs_value REAL NOT NULL,
            \\   cluster_id INTEGER
            \\ )
        , .{}, .{});
        
        // Create covering index for lookups
        try db.exec(
            \\ CREATE INDEX IF NOT EXISTS idx_river_lookup ON river_clusters (
            \\   hand_card1_rank, hand_card1_suit, hand_card2_rank, hand_card2_suit,
            \\   board_card1_rank, board_card1_suit, board_card2_rank, board_card2_suit,
            \\   board_card3_rank, board_card3_suit, board_card4_rank, board_card4_suit,
            \\   board_card5_rank, board_card5_suit
            \\ ) WHERE cluster_id IS NOT NULL
        , .{}, .{});
        
        // Turn table
        try db.exec(
            \\ CREATE TABLE IF NOT EXISTS turn_clusters (
            \\   combo_id INTEGER PRIMARY KEY,
            \\   hand_card1_rank INTEGER NOT NULL,
            \\   hand_card1_suit TEXT NOT NULL,
            \\   hand_card2_rank INTEGER NOT NULL,
            \\   hand_card2_suit TEXT NOT NULL,
            \\   board_card1_rank INTEGER NOT NULL,
            \\   board_card1_suit TEXT NOT NULL,
            \\   board_card2_rank INTEGER NOT NULL,
            \\   board_card2_suit TEXT NOT NULL,
            \\   board_card3_rank INTEGER NOT NULL,
            \\   board_card3_suit TEXT NOT NULL,
            \\   board_card4_rank INTEGER NOT NULL,
            \\   board_card4_suit TEXT NOT NULL,
            \\   distribution BLOB NOT NULL,
            \\   cluster_id INTEGER
            \\ )
        , .{}, .{});
        
        // Flop table
        try db.exec(
            \\ CREATE TABLE IF NOT EXISTS flop_clusters (
            \\   combo_id INTEGER PRIMARY KEY,
            \\   hand_card1_rank INTEGER NOT NULL,
            \\   hand_card1_suit TEXT NOT NULL,
            \\   hand_card2_rank INTEGER NOT NULL,
            \\   hand_card2_suit TEXT NOT NULL,
            \\   board_card1_rank INTEGER NOT NULL,
            \\   board_card1_suit TEXT NOT NULL,
            \\   board_card2_rank INTEGER NOT NULL,
            \\   board_card2_suit TEXT NOT NULL,
            \\   board_card3_rank INTEGER NOT NULL,
            \\   board_card3_suit TEXT NOT NULL,
            \\   distribution BLOB NOT NULL,
            \\   cluster_id INTEGER
            \\ )
        , .{}, .{});
        
        // Checkpoint table for resumable processing
        try db.exec(
            \\ CREATE TABLE IF NOT EXISTS checkpoints (
            \\   stage TEXT PRIMARY KEY,
            \\   last_combo_id INTEGER NOT NULL,
            \\   timestamp INTEGER NOT NULL,
            \\   metadata TEXT
            \\ )
        , .{}, .{});
    }
    
    // Optimized batch insertion methods
    pub fn storeRiverBatch(self: *OptimizedStorage, entries: []const WriteBuffer.RiverEntry) !void {
        // Begin transaction
        try self.db.exec("BEGIN IMMEDIATE", .{}, .{});
        defer self.db.exec("COMMIT", .{}, .{}) catch |err| {
            self.db.exec("ROLLBACK", .{}, .{}) catch {};
            return err;
        };
        
        for (entries) |entry| {
            try self.river_insert_stmt.reset();
            try self.river_insert_stmt.bind(.{
                entry.combo_id,
                entry.hand_cards[0].rank,
                entry.hand_cards[0].suit,
                entry.hand_cards[1].rank,
                entry.hand_cards[1].suit,
                entry.board_cards[0].rank,
                entry.board_cards[0].suit,
                entry.board_cards[1].rank,
                entry.board_cards[1].suit,
                entry.board_cards[2].rank,
                entry.board_cards[2].suit,
                entry.board_cards[3].rank,
                entry.board_cards[3].suit,
                entry.board_cards[4].rank,
                entry.board_cards[4].suit,
                entry.ehs_value,
                entry.cluster_id,
            });
            _ = try self.river_insert_stmt.step();
        }
        
        _ = self.total_writes.fetchAdd(entries.len, .monotonic);
    }
    
    pub fn storeTurnBatch(self: *OptimizedStorage, entries: []const WriteBuffer.TurnEntry) !void {
        try self.db.exec("BEGIN IMMEDIATE", .{}, .{});
        defer self.db.exec("COMMIT", .{}, .{}) catch |err| {
            self.db.exec("ROLLBACK", .{}, .{}) catch {};
            return err;
        };
        
        for (entries) |entry| {
            // Serialize distribution as blob
            const dist_blob = std.mem.sliceAsBytes(entry.distribution);
            
            try self.turn_insert_stmt.reset();
            try self.turn_insert_stmt.bind(.{
                entry.combo_id,
                entry.hand_cards[0].rank,
                entry.hand_cards[0].suit,
                entry.hand_cards[1].rank,
                entry.hand_cards[1].suit,
                entry.board_cards[0].rank,
                entry.board_cards[0].suit,
                entry.board_cards[1].rank,
                entry.board_cards[1].suit,
                entry.board_cards[2].rank,
                entry.board_cards[2].suit,
                entry.board_cards[3].rank,
                entry.board_cards[3].suit,
                sqlite.Blob{ .data = dist_blob },
                entry.cluster_id,
            });
            _ = try self.turn_insert_stmt.step();
        }
        
        _ = self.total_writes.fetchAdd(entries.len, .monotonic);
    }
    
    pub fn storeFlopBatch(self: *OptimizedStorage, entries: []const WriteBuffer.FlopEntry) !void {
        try self.db.exec("BEGIN IMMEDIATE", .{}, .{});
        defer self.db.exec("COMMIT", .{}, .{}) catch |err| {
            self.db.exec("ROLLBACK", .{}, .{}) catch {};
            return err;
        };
        
        for (entries) |entry| {
            const dist_blob = std.mem.sliceAsBytes(entry.distribution);
            
            try self.flop_insert_stmt.reset();
            try self.flop_insert_stmt.bind(.{
                entry.combo_id,
                entry.hand_cards[0].rank,
                entry.hand_cards[0].suit,
                entry.hand_cards[1].rank,
                entry.hand_cards[1].suit,
                entry.board_cards[0].rank,
                entry.board_cards[0].suit,
                entry.board_cards[1].rank,
                entry.board_cards[1].suit,
                entry.board_cards[2].rank,
                entry.board_cards[2].suit,
                sqlite.Blob{ .data = dist_blob },
                entry.cluster_id,
            });
            _ = try self.flop_insert_stmt.step();
        }
        
        _ = self.total_writes.fetchAdd(entries.len, .monotonic);
    }
    
    // Thread-safe buffered write methods
    pub fn writeRiverEntry(
        self: *OptimizedStorage,
        combo_id: i32,
        hand: []const Card,
        board: []const Card,
        ehs: f32,
        cluster_id: ?i32,
    ) !void {
        self.write_buffer.mutex.lock();
        defer self.write_buffer.mutex.unlock();
        
        try self.write_buffer.river_batch.append(.{
            .combo_id = combo_id,
            .hand_cards = [2]Card{ hand[0], hand[1] },
            .board_cards = [5]Card{ board[0], board[1], board[2], board[3], board[4] },
            .ehs_value = ehs,
            .cluster_id = cluster_id,
        });
        
        if (self.write_buffer.river_batch.items.len >= self.write_buffer.max_size) {
            try self.flushRiverBuffer();
        }
    }
    
    pub fn writeTurnEntry(
        self: *OptimizedStorage,
        combo_id: i32,
        hand: []const Card,
        board: []const Card,
        distribution: []const f32,
        cluster_id: ?i32,
    ) !void {
        self.write_buffer.mutex.lock();
        defer self.write_buffer.mutex.unlock();
        
        const dist_copy = try self.allocator.dupe(f32, distribution);
        
        try self.write_buffer.turn_batch.append(.{
            .combo_id = combo_id,
            .hand_cards = [2]Card{ hand[0], hand[1] },
            .board_cards = [4]Card{ board[0], board[1], board[2], board[3] },
            .distribution = dist_copy,
            .cluster_id = cluster_id,
        });
        
        if (self.write_buffer.turn_batch.items.len >= self.write_buffer.max_size) {
            try self.flushTurnBuffer();
        }
    }
    
    pub fn writeFlopEntry(
        self: *OptimizedStorage,
        combo_id: i32,
        hand: []const Card,
        board: []const Card,
        distribution: []const f32,
        cluster_id: ?i32,
    ) !void {
        self.write_buffer.mutex.lock();
        defer self.write_buffer.mutex.unlock();
        
        const dist_copy = try self.allocator.dupe(f32, distribution);
        
        try self.write_buffer.flop_batch.append(.{
            .combo_id = combo_id,
            .hand_cards = [2]Card{ hand[0], hand[1] },
            .board_cards = [3]Card{ board[0], board[1], board[2] },
            .distribution = dist_copy,
            .cluster_id = cluster_id,
        });
        
        if (self.write_buffer.flop_batch.items.len >= self.write_buffer.max_size) {
            try self.flushFlopBuffer();
        }
    }
    
    fn flushRiverBuffer(self: *OptimizedStorage) !void {
        if (self.write_buffer.river_batch.items.len == 0) return;
        
        try self.storeRiverBatch(self.write_buffer.river_batch.items);
        self.write_buffer.river_batch.clearRetainingCapacity();
        _ = self.total_flushes.fetchAdd(1, .monotonic);
    }
    
    fn flushTurnBuffer(self: *OptimizedStorage) !void {
        if (self.write_buffer.turn_batch.items.len == 0) return;
        
        try self.storeTurnBatch(self.write_buffer.turn_batch.items);
        
        // Free distributions
        for (self.write_buffer.turn_batch.items) |entry| {
            self.allocator.free(entry.distribution);
        }
        
        self.write_buffer.turn_batch.clearRetainingCapacity();
        _ = self.total_flushes.fetchAdd(1, .monotonic);
    }
    
    fn flushFlopBuffer(self: *OptimizedStorage) !void {
        if (self.write_buffer.flop_batch.items.len == 0) return;
        
        try self.storeFlopBatch(self.write_buffer.flop_batch.items);
        
        // Free distributions
        for (self.write_buffer.flop_batch.items) |entry| {
            self.allocator.free(entry.distribution);
        }
        
        self.write_buffer.flop_batch.clearRetainingCapacity();
        _ = self.total_flushes.fetchAdd(1, .monotonic);
    }
    
    pub fn flush(self: *OptimizedStorage) !void {
        self.write_buffer.mutex.lock();
        defer self.write_buffer.mutex.unlock();
        
        try self.flushRiverBuffer();
        try self.flushTurnBuffer();
        try self.flushFlopBuffer();
    }
    
    // Checkpoint management for resumable processing
    pub fn saveCheckpoint(self: *OptimizedStorage, stage: []const u8, combo_id: i32, metadata: ?[]const u8) !void {
        const query =
            \\ INSERT OR REPLACE INTO checkpoints (stage, last_combo_id, timestamp, metadata)
            \\ VALUES (?, ?, ?, ?)
        ;
        
        const timestamp = std.time.timestamp();
        try self.db.exec(query, .{}, .{ stage, combo_id, timestamp, metadata orelse "" });
    }
    
    pub fn loadCheckpoint(self: *OptimizedStorage, stage: []const u8) !?i32 {
        const query =
            \\ SELECT last_combo_id FROM checkpoints WHERE stage = ?
        ;
        
        const stmt = try self.db.prepare(query);
        defer stmt.deinit();
        
        try stmt.bind(.{stage});
        if (try stmt.step()) |row| {
            return row.int(0);
        }
        
        return null;
    }
    
    // Statistics
    pub fn getStatistics(self: *OptimizedStorage) void {
        const writes = self.total_writes.load(.acquire);
        const flushes = self.total_flushes.load(.acquire);
        
        std.debug.print("\n📊 Storage Statistics:\n", .{});
        std.debug.print("  Total writes: {}\n", .{writes});
        std.debug.print("  Total flushes: {}\n", .{flushes});
        std.debug.print("  Average batch size: {}\n", .{if (flushes > 0) writes / flushes else 0});
        
        // Get database stats
        const page_count = self.db.oneValue(i32, "PRAGMA page_count", .{}, .{}) catch 0;
        const page_size = self.db.oneValue(i32, "PRAGMA page_size", .{}, .{}) catch 0;
        const db_size_mb = (page_count * page_size) / (1024 * 1024);
        
        std.debug.print("  Database size: {} MB\n", .{db_size_mb});
    }
};

// Memory-mapped file for ultra-fast lookups
pub const MappedLUT = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    data: []align(std.mem.page_size) u8,
    header: *LUTHeader,
    entries: []LUTEntry,
    
    const LUTHeader = extern struct {
        magic: u32,
        version: u32,
        n_entries: u32,
        n_clusters: u32,
        stage: u32, // 0=river, 1=turn, 2=flop
        reserved: [44]u8,
    };
    
    const LUTEntry = extern struct {
        combo_hash: u64,
        cluster_id: u32,
        padding: u32,
    };
    
    pub fn create(allocator: std.mem.Allocator, path: []const u8, n_entries: usize, n_clusters: usize, stage: u32) !MappedLUT {
        const file = try std.fs.cwd().createFile(path, .{ .read = true });
        
        const header_size = @sizeOf(LUTHeader);
        const entries_size = n_entries * @sizeOf(LUTEntry);
        const total_size = header_size + entries_size;
        
        try file.setEndPos(total_size);
        
        const data = try std.posix.mmap(
            null,
            total_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        );
        
        const header = @as(*LUTHeader, @ptrCast(@alignCast(data.ptr)));
        header.* = .{
            .magic = 0x4C555431, // "LUT1"
            .version = 1,
            .n_entries = @intCast(n_entries),
            .n_clusters = @intCast(n_clusters),
            .stage = stage,
            .reserved = [_]u8{0} ** 44,
        };
        
        const entries = @as([*]LUTEntry, @ptrCast(@alignCast(data.ptr + header_size)))[0..n_entries];
        
        return MappedLUT{
            .allocator = allocator,
            .file = file,
            .data = data,
            .header = header,
            .entries = entries,
        };
    }
    
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !MappedLUT {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
        const file_size = try file.getEndPos();
        
        const data = try std.posix.mmap(
            null,
            file_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        );
        
        const header = @as(*LUTHeader, @ptrCast(@alignCast(data.ptr)));
        if (header.magic != 0x4C555431) {
            return error.InvalidMagic;
        }
        
        const entries = @as([*]LUTEntry, @ptrCast(@alignCast(data.ptr + @sizeOf(LUTHeader))))[0..header.n_entries];
        
        return MappedLUT{
            .allocator = allocator,
            .file = file,
            .data = data,
            .header = header,
            .entries = entries,
        };
    }
    
    pub fn deinit(self: *MappedLUT) void {
        std.posix.munmap(self.data);
        self.file.close();
    }
    
    pub fn set(self: *MappedLUT, index: usize, hash: u64, cluster_id: u32) void {
        self.entries[index] = .{
            .combo_hash = hash,
            .cluster_id = cluster_id,
            .padding = 0,
        };
    }
    
    // Binary search for fast lookup
    pub fn lookup(self: *MappedLUT, hash: u64) ?u32 {
        var left: usize = 0;
        var right: usize = self.entries.len;
        
        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = self.entries[mid];
            
            if (entry.combo_hash == hash) {
                return entry.cluster_id;
            } else if (entry.combo_hash < hash) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        
        return null;
    }
    
    // Sort entries for binary search
    pub fn sort(self: *MappedLUT) void {
        std.sort.block(LUTEntry, self.entries, {}, struct {
            fn lessThan(_: void, a: LUTEntry, b: LUTEntry) bool {
                return a.combo_hash < b.combo_hash;
            }
        }.lessThan);
    }
};