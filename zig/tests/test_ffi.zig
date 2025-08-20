// Tests for C FFI interface

const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");

test "c api basic initialization" {
    // Test library initialization
    const init_result = poker_ai.c_api.poker_ai_init();
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, init_result);
    
    // Test cleanup
    poker_ai.c_api.poker_ai_cleanup();
}

test "c api version information" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    const major = poker_ai.c_api.poker_ai_version_major();
    const minor = poker_ai.c_api.poker_ai_version_minor();
    const patch = poker_ai.c_api.poker_ai_version_patch();
    
    try testing.expectEqual(@as(u32, 0), major);
    try testing.expectEqual(@as(u32, 1), minor);
    try testing.expectEqual(@as(u32, 0), patch);
}

test "c api hand evaluator creation and destruction" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Create hand evaluator
    const handle = poker_ai.c_api.poker_hand_evaluator_create();
    try testing.expect(handle != 0);
    
    // Destroy hand evaluator
    const destroy_result = poker_ai.c_api.poker_hand_evaluator_destroy(handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, destroy_result);
    
    // Destroying again should fail
    const destroy_again = poker_ai.c_api.poker_hand_evaluator_destroy(handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.INVALID_PARAMETER, destroy_again);
}

test "c api hand evaluation" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    const handle = poker_ai.c_api.poker_hand_evaluator_create();
    defer _ = poker_ai.c_api.poker_hand_evaluator_destroy(handle);
    
    // Test 5-card evaluation
    const cards_5 = [5]u8{ 0, 1, 2, 3, 4 };
    const result_5 = poker_ai.c_api.poker_hand_evaluate_5(handle, &cards_5);
    try testing.expect(result_5 > 0);
    
    // Test 7-card evaluation
    const cards_7 = [7]u8{ 0, 1, 2, 3, 4, 5, 6 };
    const result_7 = poker_ai.c_api.poker_hand_evaluate_7(handle, &cards_7);
    try testing.expect(result_7 > 0);
    
    // Test with null pointer (should return 0)
    const null_result = poker_ai.c_api.poker_hand_evaluate_5(handle, null);
    try testing.expectEqual(@as(u32, 0), null_result);
}

test "c api game state creation and destruction" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Create game state
    const handle = poker_ai.c_api.poker_game_state_create(2, 5, 10);
    try testing.expect(handle != 0);
    
    // Test basic game state queries
    const pot = poker_ai.c_api.poker_game_state_get_pot(handle);
    try testing.expectEqual(@as(u32, 0), pot);
    
    const current_player = poker_ai.c_api.poker_game_state_get_current_player(handle);
    try testing.expectEqual(@as(u8, 0), current_player);
    
    const is_terminal = poker_ai.c_api.poker_game_state_is_terminal(handle);
    try testing.expectEqual(@as(c_int, 0), is_terminal);
    
    // Destroy game state
    const destroy_result = poker_ai.c_api.poker_game_state_destroy(handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, destroy_result);
}

test "c api game state operations" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    const handle = poker_ai.c_api.poker_game_state_create(2, 5, 10);
    defer _ = poker_ai.c_api.poker_game_state_destroy(handle);
    
    // Deal hole cards
    const deal_result1 = poker_ai.c_api.poker_game_state_deal_hole_cards(handle, 0, 0, 1);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, deal_result1);
    
    const deal_result2 = poker_ai.c_api.poker_game_state_deal_hole_cards(handle, 1, 2, 3);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, deal_result2);
    
    // Invalid player ID should fail
    const deal_invalid = poker_ai.c_api.poker_game_state_deal_hole_cards(handle, 5, 0, 1);
    try testing.expectEqual(poker_ai.c_api.PokerError.INVALID_PARAMETER, deal_invalid);
    
    // Apply actions
    const action_call = poker_ai.c_api.poker_game_state_apply_action(handle, @intFromEnum(poker_ai.game_state.ActionType.call), 0);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, action_call);
    
    const action_raise = poker_ai.c_api.poker_game_state_apply_action(handle, @intFromEnum(poker_ai.game_state.ActionType.raise), 20);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, action_raise);
}

test "c api cfr trainer creation and destruction" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Create CFR trainer
    const handle = poker_ai.c_api.poker_cfr_trainer_create(10, 1); // 10 iterations, 1 thread
    try testing.expect(handle != 0);
    
    // Destroy trainer
    const destroy_result = poker_ai.c_api.poker_cfr_trainer_destroy(handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, destroy_result);
}

test "c api cfr training" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    const handle = poker_ai.c_api.poker_cfr_trainer_create(5, 1); // Small training run
    defer _ = poker_ai.c_api.poker_cfr_trainer_destroy(handle);
    
    // Run training
    const train_result = poker_ai.c_api.poker_cfr_trainer_train(handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, train_result);
}

test "c api strategy table operations" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Create strategy table
    const handle = poker_ai.c_api.poker_strategy_table_create();
    try testing.expect(handle != 0);
    
    // Test memory usage query
    const memory_usage = poker_ai.c_api.poker_strategy_table_get_memory_usage(handle);
    try testing.expect(memory_usage >= 0); // Should be non-negative
    
    // Destroy strategy table
    const destroy_result = poker_ai.c_api.poker_strategy_table_destroy(handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, destroy_result);
}

test "c api card utility functions" {
    // Test card creation
    const ace_spades = poker_ai.c_api.poker_card_from_rank_suit(12, 3); // Ace of spades
    try testing.expectEqual(@as(u8, 51), ace_spades);
    
    const deuce_clubs = poker_ai.c_api.poker_card_from_rank_suit(0, 0); // 2 of clubs
    try testing.expectEqual(@as(u8, 0), deuce_clubs);
    
    // Test invalid card
    const invalid_card = poker_ai.c_api.poker_card_from_rank_suit(15, 5);
    try testing.expectEqual(@as(u8, 255), invalid_card);
    
    // Test card parsing
    const rank = poker_ai.c_api.poker_card_get_rank(ace_spades);
    try testing.expectEqual(@as(u8, 12), rank);
    
    const suit = poker_ai.c_api.poker_card_get_suit(ace_spades);
    try testing.expectEqual(@as(u8, 3), suit);
}

test "c api error handling" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Test operations with invalid handles
    const invalid_handle: u32 = 999999;
    
    const eval_result = poker_ai.c_api.poker_hand_evaluate_5(invalid_handle, null);
    try testing.expectEqual(@as(u32, 0), eval_result);
    
    const destroy_result = poker_ai.c_api.poker_hand_evaluator_destroy(invalid_handle);
    try testing.expectEqual(poker_ai.c_api.PokerError.INVALID_PARAMETER, destroy_result);
    
    const pot_result = poker_ai.c_api.poker_game_state_get_pot(invalid_handle);
    try testing.expectEqual(@as(u32, 0), pot_result);
    
    const player_result = poker_ai.c_api.poker_game_state_get_current_player(invalid_handle);
    try testing.expectEqual(@as(u8, 255), player_result);
}

test "c api file operations" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    const strategy_handle = poker_ai.c_api.poker_strategy_table_create();
    defer _ = poker_ai.c_api.poker_strategy_table_destroy(strategy_handle);
    
    const cfr_handle = poker_ai.c_api.poker_cfr_trainer_create(5, 1);
    defer _ = poker_ai.c_api.poker_cfr_trainer_destroy(cfr_handle);
    
    // Test save/load with null paths (should fail)
    const save_null = poker_ai.c_api.poker_strategy_table_save(strategy_handle, null);
    try testing.expectEqual(poker_ai.c_api.PokerError.INVALID_PARAMETER, save_null);
    
    const load_null = poker_ai.c_api.poker_cfr_trainer_load_strategy(cfr_handle, null);
    try testing.expectEqual(poker_ai.c_api.PokerError.INVALID_PARAMETER, load_null);
    
    // Test with non-existent file (should fail)
    const load_missing = poker_ai.c_api.poker_cfr_trainer_load_strategy(cfr_handle, "/tmp/non_existent_file.dat");
    try testing.expectEqual(poker_ai.c_api.PokerError.FILE_ERROR, load_missing);
}

test "c api handle lifecycle" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Create multiple handles of different types
    const eval_handle = poker_ai.c_api.poker_hand_evaluator_create();
    const game_handle = poker_ai.c_api.poker_game_state_create(2, 5, 10);
    const strategy_handle = poker_ai.c_api.poker_strategy_table_create();
    const cfr_handle = poker_ai.c_api.poker_cfr_trainer_create(1, 1);
    
    // All handles should be valid and different
    try testing.expect(eval_handle != 0);
    try testing.expect(game_handle != 0);
    try testing.expect(strategy_handle != 0);
    try testing.expect(cfr_handle != 0);
    
    try testing.expect(eval_handle != game_handle);
    try testing.expect(game_handle != strategy_handle);
    try testing.expect(strategy_handle != cfr_handle);
    
    // Clean up all handles
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, poker_ai.c_api.poker_hand_evaluator_destroy(eval_handle));
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, poker_ai.c_api.poker_game_state_destroy(game_handle));
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, poker_ai.c_api.poker_strategy_table_destroy(strategy_handle));
    try testing.expectEqual(poker_ai.c_api.PokerError.SUCCESS, poker_ai.c_api.poker_cfr_trainer_destroy(cfr_handle));
}

test "c api thread safety setup" {
    // Test multiple initializations (should be safe)
    _ = poker_ai.c_api.poker_ai_init();
    _ = poker_ai.c_api.poker_ai_init();
    _ = poker_ai.c_api.poker_ai_init();
    
    // Multiple cleanups should also be safe
    poker_ai.c_api.poker_ai_cleanup();
    poker_ai.c_api.poker_ai_cleanup();
    poker_ai.c_api.poker_ai_cleanup();
}

test "c api large handle allocation" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Test creating many handles (should work up to reasonable limits)
    var handles: [100]u32 = undefined;
    var created_count: usize = 0;
    
    for (&handles) |*handle| {
        handle.* = poker_ai.c_api.poker_hand_evaluator_create();
        if (handle.* != 0) {
            created_count += 1;
        }
    }
    
    // Should be able to create at least some handles
    try testing.expect(created_count > 0);
    
    // Clean up all created handles
    for (handles[0..created_count]) |handle| {
        _ = poker_ai.c_api.poker_hand_evaluator_destroy(handle);
    }
}

test "c api concurrent handle operations" {
    _ = poker_ai.c_api.poker_ai_init();
    defer poker_ai.c_api.poker_ai_cleanup();
    
    // Create multiple evaluators and use them concurrently
    const handle1 = poker_ai.c_api.poker_hand_evaluator_create();
    const handle2 = poker_ai.c_api.poker_hand_evaluator_create();
    defer _ = poker_ai.c_api.poker_hand_evaluator_destroy(handle1);
    defer _ = poker_ai.c_api.poker_hand_evaluator_destroy(handle2);
    
    const cards = [5]u8{ 0, 1, 2, 3, 4 };
    
    // Should be able to use both handles simultaneously
    const result1 = poker_ai.c_api.poker_hand_evaluate_5(handle1, &cards);
    const result2 = poker_ai.c_api.poker_hand_evaluate_5(handle2, &cards);
    
    try testing.expect(result1 > 0);
    try testing.expect(result2 > 0);
    try testing.expectEqual(result1, result2); // Same input should give same result
}