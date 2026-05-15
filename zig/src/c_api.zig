// C API for Python FFI integration
// Exposes poker AI functionality through C interface

const std = @import("std");
const main = @import("main.zig");
const hand_eval = @import("hand_eval.zig");
const game_state = @import("game_state.zig");
const cfr = @import("cfr.zig");
const parallel_cfr = @import("parallel_cfr.zig");
const strategy_table = @import("strategy_table.zig");

// C-compatible error codes
pub const PokerError = enum(c_int) {
    SUCCESS = 0,
    INVALID_PARAMETER = -1,
    ALLOCATION_ERROR = -2,
    GAME_STATE_ERROR = -3,
    STRATEGY_ERROR = -4,
    FILE_ERROR = -5,
};

// Opaque handles for C API
const PokerHandleType = enum {
    hand_evaluator,
    game_state,
    cfr_trainer,
    strategy_table,
};

const PokerHandle = struct {
    handle_type: PokerHandleType,
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
};

const HandleMap = std.hash_map.HashMap(u32, PokerHandle, std.hash_map.AutoContext(u32), 80);

// Global handle management
var g_handles = HandleMap.init(std.heap.c_allocator);
var g_next_handle_id: u32 = 1;
var g_handle_mutex = std.Thread.Mutex{};
var init_count: usize = 0;

// Initialize the poker AI library
pub export fn poker_ai_init() PokerError {
    g_handle_mutex.lock();
    defer g_handle_mutex.unlock();

    if (init_count == 0) {
        main.init(std.heap.c_allocator);
    }
    init_count += 1;
    return PokerError.SUCCESS;
}

// Cleanup the poker AI library
pub export fn poker_ai_cleanup() void {
    g_handle_mutex.lock();
    defer g_handle_mutex.unlock();

    if (init_count == 0) return;

    init_count -= 1;
    if (init_count > 0) return;

    if (g_handles.count() > 0) {
        var iterator = g_handles.iterator();
        while (iterator.next()) |entry| {
            cleanupHandle(entry.value_ptr.*);
        }
    }
    g_handles.deinit();
    g_handles = HandleMap.init(std.heap.c_allocator);

    main.deinit();
}

// Hand Evaluator C API
pub export fn poker_hand_evaluator_create() u32 {
    const evaluator = std.heap.c_allocator.create(hand_eval.HandEvaluator) catch return 0;
    evaluator.* = hand_eval.HandEvaluator.init();

    return registerHandle(PokerHandle{
        .handle_type = .hand_evaluator,
        .ptr = evaluator,
        .allocator = std.heap.c_allocator,
    });
}

pub export fn poker_hand_evaluator_destroy(handle: u32) PokerError {
    return destroyHandle(handle);
}

pub export fn poker_hand_evaluate_5(handle: u32, cards: [*c]const u8) u32 {
    const evaluator = getHandle(handle, .hand_evaluator) orelse return 0;
    const eval_ptr: *hand_eval.HandEvaluator = @ptrCast(@alignCast(evaluator.ptr));

    if (cards == null) return 0;

    // Convert u8 to Card (Card is just u32 in hand_eval)
    const card_array = [5]hand_eval.Card{ @as(hand_eval.Card, cards[0]), @as(hand_eval.Card, cards[1]), @as(hand_eval.Card, cards[2]), @as(hand_eval.Card, cards[3]), @as(hand_eval.Card, cards[4]) };
    const result = eval_ptr.evaluateFive(card_array);

    return result;
}

pub export fn poker_hand_evaluate_7(handle: u32, cards: [*c]const u8) u32 {
    const evaluator = getHandle(handle, .hand_evaluator) orelse return 0;
    const eval_ptr: *hand_eval.HandEvaluator = @ptrCast(@alignCast(evaluator.ptr));

    if (cards == null) return 0;

    // Convert u8 to Card (Card is just u32 in hand_eval)
    const card_array = [7]hand_eval.Card{ @as(hand_eval.Card, cards[0]), @as(hand_eval.Card, cards[1]), @as(hand_eval.Card, cards[2]), @as(hand_eval.Card, cards[3]), @as(hand_eval.Card, cards[4]), @as(hand_eval.Card, cards[5]), @as(hand_eval.Card, cards[6]) };
    const result = eval_ptr.evaluateSeven(card_array);

    return result;
}

// Game State C API
pub export fn poker_game_state_create(num_players: u8, small_blind: u32, big_blind: u32) u32 {
    const game = std.heap.c_allocator.create(game_state.GameState) catch return 0;
    game.* = game_state.GameState.init(std.heap.c_allocator, num_players, small_blind, big_blind) catch {
        std.heap.c_allocator.destroy(game);
        return 0;
    };

    return registerHandle(PokerHandle{
        .handle_type = .game_state,
        .ptr = game,
        .allocator = std.heap.c_allocator,
    });
}

pub export fn poker_game_state_destroy(handle: u32) PokerError {
    return destroyHandle(handle);
}

pub export fn poker_game_state_deal_hole_cards(handle: u32, player_id: u8, card1: u8, card2: u8) PokerError {
    const game = getHandle(handle, .game_state) orelse return PokerError.INVALID_PARAMETER;
    const game_ptr: *game_state.GameState = @ptrCast(@alignCast(game.ptr));

    if (player_id >= game_ptr.num_players) return PokerError.INVALID_PARAMETER;

    game_ptr.players[player_id].hand = game_state.Hand.init(card1, card2);
    return PokerError.SUCCESS;
}

pub export fn poker_game_state_apply_action(handle: u32, action_type: u8, amount: u32) PokerError {
    const game = getHandle(handle, .game_state) orelse return PokerError.INVALID_PARAMETER;
    const game_ptr: *game_state.GameState = @ptrCast(@alignCast(game.ptr));

    const action = game_state.Action{
        .action_type = @enumFromInt(action_type),
        .amount = amount,
    };

    const success = game_ptr.applyAction(action) catch return PokerError.GAME_STATE_ERROR;
    return if (success) PokerError.SUCCESS else PokerError.GAME_STATE_ERROR;
}

pub export fn poker_game_state_is_terminal(handle: u32) c_int {
    const game = getHandle(handle, .game_state) orelse return -1;
    const game_ptr: *game_state.GameState = @ptrCast(@alignCast(game.ptr));

    return if (game_ptr.isTerminal()) 1 else 0;
}

pub export fn poker_game_state_get_pot(handle: u32) u32 {
    const game = getHandle(handle, .game_state) orelse return 0;
    const game_ptr: *game_state.GameState = @ptrCast(@alignCast(game.ptr));

    return game_ptr.pot;
}

pub export fn poker_game_state_get_current_player(handle: u32) u8 {
    const game = getHandle(handle, .game_state) orelse return 255;
    const game_ptr: *game_state.GameState = @ptrCast(@alignCast(game.ptr));

    return game_ptr.current_player;
}

// CFR Trainer C API
pub export fn poker_cfr_trainer_create(iterations: u32, num_threads: u32) u32 {
    const config = cfr.CFRConfig{
        .iterations = iterations,
        .exploration_probability = 0.6,
        .prune_threshold = -300.0,
        .discount_alpha = 1.5,
        .discount_beta = 0.0,
    };

    const trainer = std.heap.c_allocator.create(parallel_cfr.ParallelCFRTrainer) catch return 0;
    trainer.* = parallel_cfr.ParallelCFRTrainer.init(std.heap.c_allocator, config, num_threads);

    return registerHandle(PokerHandle{
        .handle_type = .cfr_trainer,
        .ptr = trainer,
        .allocator = std.heap.c_allocator,
    });
}

pub export fn poker_cfr_trainer_destroy(handle: u32) PokerError {
    return destroyHandle(handle);
}

pub export fn poker_cfr_trainer_train(handle: u32) PokerError {
    const trainer = getHandle(handle, .cfr_trainer) orelse return PokerError.INVALID_PARAMETER;
    const trainer_ptr: *parallel_cfr.ParallelCFRTrainer = @ptrCast(@alignCast(trainer.ptr));

    trainer_ptr.train() catch return PokerError.STRATEGY_ERROR;
    return PokerError.SUCCESS;
}

pub export fn poker_cfr_trainer_save_strategy(handle: u32, file_path: [*c]const u8) PokerError {
    const trainer = getHandle(handle, .cfr_trainer) orelse return PokerError.INVALID_PARAMETER;
    const trainer_ptr: *parallel_cfr.ParallelCFRTrainer = @ptrCast(@alignCast(trainer.ptr));

    if (file_path == null) return PokerError.INVALID_PARAMETER;

    const path_slice = std.mem.span(file_path);
    trainer_ptr.saveStrategy(path_slice) catch return PokerError.FILE_ERROR;

    return PokerError.SUCCESS;
}

pub export fn poker_cfr_trainer_load_strategy(handle: u32, file_path: [*c]const u8) PokerError {
    const trainer = getHandle(handle, .cfr_trainer) orelse return PokerError.INVALID_PARAMETER;
    const trainer_ptr: *parallel_cfr.ParallelCFRTrainer = @ptrCast(@alignCast(trainer.ptr));

    if (file_path == null) return PokerError.INVALID_PARAMETER;

    const path_slice = std.mem.span(file_path);
    trainer_ptr.loadStrategy(path_slice) catch return PokerError.FILE_ERROR;

    return PokerError.SUCCESS;
}

// Strategy Table C API
pub export fn poker_strategy_table_create() u32 {
    const table = std.heap.c_allocator.create(strategy_table.StrategyTable) catch return 0;
    table.* = strategy_table.StrategyTable.init(std.heap.c_allocator);

    return registerHandle(PokerHandle{
        .handle_type = .strategy_table,
        .ptr = table,
        .allocator = std.heap.c_allocator,
    });
}

pub export fn poker_strategy_table_destroy(handle: u32) PokerError {
    return destroyHandle(handle);
}

pub export fn poker_strategy_table_save(handle: u32, file_path: [*c]const u8) PokerError {
    const table = getHandle(handle, .strategy_table) orelse return PokerError.INVALID_PARAMETER;
    const table_ptr: *strategy_table.StrategyTable = @ptrCast(@alignCast(table.ptr));

    if (file_path == null) return PokerError.INVALID_PARAMETER;

    const path_slice = std.mem.span(file_path);
    table_ptr.saveToFile(path_slice) catch return PokerError.FILE_ERROR;

    return PokerError.SUCCESS;
}

pub export fn poker_strategy_table_load(handle: u32, file_path: [*c]const u8) PokerError {
    const table = getHandle(handle, .strategy_table) orelse return PokerError.INVALID_PARAMETER;
    const table_ptr: *strategy_table.StrategyTable = @ptrCast(@alignCast(table.ptr));

    if (file_path == null) return PokerError.INVALID_PARAMETER;

    const path_slice = std.mem.span(file_path);
    table_ptr.loadFromFile(path_slice) catch return PokerError.FILE_ERROR;

    return PokerError.SUCCESS;
}

pub export fn poker_strategy_table_get_memory_usage(handle: u32) usize {
    const table = getHandle(handle, .strategy_table) orelse return 0;
    const table_ptr: *strategy_table.StrategyTable = @ptrCast(@alignCast(table.ptr));

    return table_ptr.getMemoryUsage();
}

// Utility functions for card operations
pub export fn poker_card_from_rank_suit(rank: u8, suit: u8) u8 {
    if (rank > 12 or suit > 3) return 255; // Invalid card
    return (rank << 2) | suit;
}

pub export fn poker_card_get_rank(card: u8) u8 {
    // Extract rank from card representation (bits 2-5)
    return card >> 2;
}

pub export fn poker_card_get_suit(card: u8) u8 {
    // Extract suit from card representation (bits 0-1)
    return card & 0x03;
}

// Helper functions
fn registerHandle(handle: PokerHandle) u32 {
    g_handle_mutex.lock();
    defer g_handle_mutex.unlock();

    const handle_id = g_next_handle_id;
    g_next_handle_id += 1;

    g_handles.put(handle_id, handle) catch return 0;
    return handle_id;
}

fn getHandle(handle_id: u32, expected_type: PokerHandleType) ?*PokerHandle {
    g_handle_mutex.lock();
    defer g_handle_mutex.unlock();

    if (g_handles.getPtr(handle_id)) |handle| {
        if (handle.handle_type == expected_type) {
            return handle;
        }
    }
    return null;
}

fn destroyHandle(handle_id: u32) PokerError {
    g_handle_mutex.lock();
    defer g_handle_mutex.unlock();

    if (g_handles.fetchRemove(handle_id)) |kv| {
        cleanupHandle(kv.value);
        return PokerError.SUCCESS;
    }

    return PokerError.INVALID_PARAMETER;
}

fn cleanupHandle(handle: PokerHandle) void {
    switch (handle.handle_type) {
        .hand_evaluator => {
            const evaluator: *hand_eval.HandEvaluator = @ptrCast(@alignCast(handle.ptr));
            // HandEvaluator has no deinit
            handle.allocator.destroy(evaluator);
        },
        .game_state => {
            const game: *game_state.GameState = @ptrCast(@alignCast(handle.ptr));
            game.deinit();
            handle.allocator.destroy(game);
        },
        .cfr_trainer => {
            const trainer: *parallel_cfr.ParallelCFRTrainer = @ptrCast(@alignCast(handle.ptr));
            trainer.deinit();
            handle.allocator.destroy(trainer);
        },
        .strategy_table => {
            const table: *strategy_table.StrategyTable = @ptrCast(@alignCast(handle.ptr));
            table.deinit();
            handle.allocator.destroy(table);
        },
    }
}

// Version information
pub export fn poker_ai_version_major() u32 {
    return main.version.major;
}

pub export fn poker_ai_version_minor() u32 {
    return main.version.minor;
}

pub export fn poker_ai_version_patch() u32 {
    return main.version.patch;
}
