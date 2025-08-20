const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const Card = @import("eval_card.zig").Card;
const LUTBuilder = @import("lut_builder.zig").LUTBuilder;

pub const StorageError = error{
    DatabaseOpenFailed,
    StatementPrepareFailed,
    ExecutionFailed,
    BindFailed,
    InvalidData,
};

pub const Storage = struct {
    db: ?*c.sqlite3,
    chunk_size: usize,
    allocator: std.mem.Allocator,
    pending_operations: usize,
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8, chunk_size: usize) !Storage {
        var db: ?*c.sqlite3 = null;
        
        // Open database
        const db_path_z = try allocator.dupeZ(u8, db_path);
        defer allocator.free(db_path_z);
        
        if (c.sqlite3_open(db_path_z.ptr, &db) != c.SQLITE_OK) {
            return StorageError.DatabaseOpenFailed;
        }
        
        var storage = Storage{
            .db = db,
            .chunk_size = chunk_size,
            .allocator = allocator,
            .pending_operations = 0,
        };
        
        // Initialize database schema
        try storage.initSchema();
        
        // Set pragmas for performance
        _ = try storage.exec("PRAGMA journal_mode=WAL");
        _ = try storage.exec("PRAGMA synchronous=NORMAL");
        _ = try storage.exec("PRAGMA cache_size=-64000");
        _ = try storage.exec("PRAGMA temp_store=MEMORY");
        
        return storage;
    }
    
    pub fn deinit(self: *Storage) void {
        self.flush() catch {}; // Flush any remaining operations
        
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
        }
    }
    
    fn initSchema(self: *Storage) !void {
        // River table - stores EHS value
        _ = try self.exec(
            \\CREATE TABLE IF NOT EXISTS river_data (
            \\    combo_id INTEGER PRIMARY KEY,
            \\    hand_cards BLOB NOT NULL,
            \\    board_cards BLOB NOT NULL,
            \\    ehs REAL,
            \\    cluster_id INTEGER,
            \\    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            \\)
        );
        
        // Turn table - stores distribution over river clusters
        _ = try self.exec(
            \\CREATE TABLE IF NOT EXISTS turn_data (
            \\    combo_id INTEGER PRIMARY KEY,
            \\    hand_cards BLOB NOT NULL,
            \\    board_cards BLOB NOT NULL,
            \\    distribution BLOB,
            \\    cluster_id INTEGER,
            \\    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            \\)
        );
        
        // Flop table - stores distribution over turn clusters
        _ = try self.exec(
            \\CREATE TABLE IF NOT EXISTS flop_data (
            \\    combo_id INTEGER PRIMARY KEY,
            \\    hand_cards BLOB NOT NULL,
            \\    board_cards BLOB NOT NULL,
            \\    distribution BLOB,
            \\    cluster_id INTEGER,
            \\    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            \\)
        );
        
        // Preflop table
        _ = try self.exec(
            \\CREATE TABLE IF NOT EXISTS preflop_data (
            \\    combo_id INTEGER PRIMARY KEY,
            \\    hand_cards BLOB NOT NULL,
            \\    cluster_id INTEGER,
            \\    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            \\)
        );
        
        // Create indices
        _ = try self.exec("CREATE INDEX IF NOT EXISTS idx_river_cluster ON river_data(cluster_id)");
        _ = try self.exec("CREATE INDEX IF NOT EXISTS idx_turn_cluster ON turn_data(cluster_id)");
        _ = try self.exec("CREATE INDEX IF NOT EXISTS idx_flop_cluster ON flop_data(cluster_id)");
        _ = try self.exec("CREATE INDEX IF NOT EXISTS idx_preflop_cluster ON preflop_data(cluster_id)");
        
        // Checkpoint table
        _ = try self.exec(
            \\CREATE TABLE IF NOT EXISTS checkpoints (
            \\    stage TEXT PRIMARY KEY,
            \\    last_processed_index INTEGER,
            \\    kmeans_state BLOB,
            \\    centroids BLOB,
            \\    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            \\)
        );
    }
    
    fn exec(self: *Storage, sql: []const u8) !void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        var err_msg: [*c]u8 = null;
        const result = c.sqlite3_exec(self.db, sql_z.ptr, null, null, &err_msg);
        
        if (result != c.SQLITE_OK) {
            if (err_msg != null) {
                std.debug.print("SQL Error: {s}\n", .{err_msg});
                c.sqlite3_free(err_msg);
            }
            return StorageError.ExecutionFailed;
        }
    }
    
    // Store river data (EHS value)
    pub fn storeRiverData(
        self: *Storage,
        combo_id: i64,
        combo: LUTBuilder.Combination,
        ehs: f32,
        cluster_id: ?u32,
    ) !void {
        // Begin transaction if needed
        if (self.pending_operations == 0) {
            _ = try self.exec("BEGIN TRANSACTION");
        }
        
        const sql = 
            \\INSERT OR REPLACE INTO river_data 
            \\(combo_id, hand_cards, board_cards, ehs, cluster_id)
            \\VALUES (?, ?, ?, ?, ?)
        ;
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return StorageError.StatementPrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        // Serialize cards as eval_card integers
        const hand_blob = try self.serializeCards(combo.hand);
        defer self.allocator.free(hand_blob);
        const board_blob = try self.serializeCards(combo.board);
        defer self.allocator.free(board_blob);
        
        // Bind parameters
        _ = c.sqlite3_bind_int64(stmt, 1, combo_id);
        _ = c.sqlite3_bind_blob(stmt, 2, hand_blob.ptr, @intCast(hand_blob.len), null);
        _ = c.sqlite3_bind_blob(stmt, 3, board_blob.ptr, @intCast(board_blob.len), null);
        _ = c.sqlite3_bind_double(stmt, 4, ehs);
        
        if (cluster_id) |cid| {
            _ = c.sqlite3_bind_int(stmt, 5, @intCast(cid));
        } else {
            _ = c.sqlite3_bind_null(stmt, 5);
        }
        
        // Execute
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return StorageError.ExecutionFailed;
        }
        
        self.pending_operations += 1;
        if (self.pending_operations >= self.chunk_size) {
            try self.flush();
        }
    }
    
    // Store turn data (distribution over river clusters)
    pub fn storeTurnData(
        self: *Storage,
        combo_id: i64,
        combo: LUTBuilder.Combination,
        distribution: []f32,
        cluster_id: ?u32,
    ) !void {
        // Begin transaction if needed
        if (self.pending_operations == 0) {
            _ = try self.exec("BEGIN TRANSACTION");
        }
        
        const sql = 
            \\INSERT OR REPLACE INTO turn_data 
            \\(combo_id, hand_cards, board_cards, distribution, cluster_id)
            \\VALUES (?, ?, ?, ?, ?)
        ;
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return StorageError.StatementPrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        // Serialize data
        const hand_blob = try self.serializeCards(combo.hand);
        defer self.allocator.free(hand_blob);
        const board_blob = try self.serializeCards(combo.board);
        defer self.allocator.free(board_blob);
        const dist_blob = try self.serializeFloats(distribution);
        defer self.allocator.free(dist_blob);
        
        // Bind parameters
        _ = c.sqlite3_bind_int64(stmt, 1, combo_id);
        _ = c.sqlite3_bind_blob(stmt, 2, hand_blob.ptr, @intCast(hand_blob.len), null);
        _ = c.sqlite3_bind_blob(stmt, 3, board_blob.ptr, @intCast(board_blob.len), null);
        _ = c.sqlite3_bind_blob(stmt, 4, dist_blob.ptr, @intCast(dist_blob.len), null);
        
        if (cluster_id) |cid| {
            _ = c.sqlite3_bind_int(stmt, 5, @intCast(cid));
        } else {
            _ = c.sqlite3_bind_null(stmt, 5);
        }
        
        // Execute
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return StorageError.ExecutionFailed;
        }
        
        self.pending_operations += 1;
        if (self.pending_operations >= self.chunk_size) {
            try self.flush();
        }
    }
    
    // Store flop data (distribution over turn clusters)
    pub fn storeFlopData(
        self: *Storage,
        combo_id: i64,
        combo: LUTBuilder.Combination,
        distribution: []f32,
        cluster_id: ?u32,
    ) !void {
        // Similar to storeTurnData but for flop table
        // Begin transaction if needed
        if (self.pending_operations == 0) {
            _ = try self.exec("BEGIN TRANSACTION");
        }
        
        const sql = 
            \\INSERT OR REPLACE INTO flop_data 
            \\(combo_id, hand_cards, board_cards, distribution, cluster_id)
            \\VALUES (?, ?, ?, ?, ?)
        ;
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return StorageError.StatementPrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        // Serialize data
        const hand_blob = try self.serializeCards(combo.hand);
        defer self.allocator.free(hand_blob);
        const board_blob = try self.serializeCards(combo.board);
        defer self.allocator.free(board_blob);
        const dist_blob = try self.serializeFloats(distribution);
        defer self.allocator.free(dist_blob);
        
        // Bind parameters
        _ = c.sqlite3_bind_int64(stmt, 1, combo_id);
        _ = c.sqlite3_bind_blob(stmt, 2, hand_blob.ptr, @intCast(hand_blob.len), null);
        _ = c.sqlite3_bind_blob(stmt, 3, board_blob.ptr, @intCast(board_blob.len), null);
        _ = c.sqlite3_bind_blob(stmt, 4, dist_blob.ptr, @intCast(dist_blob.len), null);
        
        if (cluster_id) |cid| {
            _ = c.sqlite3_bind_int(stmt, 5, @intCast(cid));
        } else {
            _ = c.sqlite3_bind_null(stmt, 5);
        }
        
        // Execute
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return StorageError.ExecutionFailed;
        }
        
        self.pending_operations += 1;
        if (self.pending_operations >= self.chunk_size) {
            try self.flush();
        }
    }
    
    // Update cluster ID after K-means clustering
    pub fn updateClusterId(
        self: *Storage,
        stage: []const u8,
        combo_id: i64,
        cluster_id: i32,
    ) !void {
        var sql_buf: [256]u8 = undefined;
        const sql = try std.fmt.bufPrint(&sql_buf,
            \\UPDATE {s}_data SET cluster_id = ? WHERE combo_id = ?
        , .{stage});
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return StorageError.StatementPrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_int(stmt, 1, cluster_id);
        _ = c.sqlite3_bind_int64(stmt, 2, combo_id);
        
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return StorageError.ExecutionFailed;
        }
    }
    
    // Flush pending operations
    pub fn flush(self: *Storage) !void {
        if (self.pending_operations > 0) {
            _ = try self.exec("COMMIT");
            self.pending_operations = 0;
        }
    }
    
    // Serialize cards to blob (stores eval_card integers)
    fn serializeCards(self: *Storage, cards: []const Card) ![]u8 {
        const blob = try self.allocator.alloc(u8, cards.len * @sizeOf(u32));
        
        for (cards, 0..) |card, i| {
            const offset = i * @sizeOf(u32);
            const eval_int = card.eval_card;
            const bytes = std.mem.asBytes(&eval_int);
            @memcpy(blob[offset..offset + @sizeOf(u32)], bytes);
        }
        
        return blob;
    }
    
    // Serialize float array to blob
    fn serializeFloats(self: *Storage, values: []const f32) ![]u8 {
        const blob = try self.allocator.alloc(u8, values.len * @sizeOf(f32));
        
        for (values, 0..) |val, i| {
            const offset = i * @sizeOf(f32);
            const bytes = std.mem.asBytes(&val);
            @memcpy(blob[offset..offset + @sizeOf(f32)], bytes);
        }
        
        return blob;
    }
    
    // Save checkpoint for resuming
    pub fn saveCheckpoint(
        self: *Storage,
        stage: []const u8,
        last_index: i64,
        kmeans_data: ?[]const u8,
        centroids_data: ?[]const u8,
    ) !void {
        const sql = 
            \\INSERT OR REPLACE INTO checkpoints 
            \\(stage, last_processed_index, kmeans_state, centroids, updated_at)
            \\VALUES (?, ?, ?, ?, datetime('now'))
        ;
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return StorageError.StatementPrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        const stage_z = try self.allocator.dupeZ(u8, stage);
        defer self.allocator.free(stage_z);
        
        _ = c.sqlite3_bind_text(stmt, 1, stage_z.ptr, -1, null);
        _ = c.sqlite3_bind_int64(stmt, 2, last_index);
        
        if (kmeans_data) |data| {
            _ = c.sqlite3_bind_blob(stmt, 3, data.ptr, @intCast(data.len), null);
        } else {
            _ = c.sqlite3_bind_null(stmt, 3);
        }
        
        if (centroids_data) |data| {
            _ = c.sqlite3_bind_blob(stmt, 4, data.ptr, @intCast(data.len), null);
        } else {
            _ = c.sqlite3_bind_null(stmt, 4);
        }
        
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return StorageError.ExecutionFailed;
        }
    }
};