// Comprehensive tests for game state management

const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");

test "player initialization" {
    var player = poker_ai.game_state.Player.init(0, 1000);
    
    try testing.expectEqual(@as(u8, 0), player.id);
    try testing.expectEqual(@as(u32, 1000), player.stack);
    try testing.expect(player.is_active);
    try testing.expect(!player.is_all_in);
    try testing.expectEqual(@as(u32, 0), player.bet_this_round);
    try testing.expectEqual(@as(u32, 0), player.total_bet);
    try testing.expect(player.hand.isEmpty());
}

test "player betting mechanics" {
    var player = poker_ai.game_state.Player.init(0, 1000);
    
    // Valid bet
    const success1 = player.bet(100);
    try testing.expect(success1);
    try testing.expectEqual(@as(u32, 900), player.stack);
    try testing.expectEqual(@as(u32, 100), player.bet_this_round);
    try testing.expectEqual(@as(u32, 100), player.total_bet);
    
    // All-in bet
    const success2 = player.bet(900);
    try testing.expect(success2);
    try testing.expectEqual(@as(u32, 0), player.stack);
    try testing.expect(player.is_all_in);
    
    // Invalid bet (exceeds stack)
    const success3 = player.bet(100);
    try testing.expect(!success3);
}

test "player folding" {
    var player = poker_ai.game_state.Player.init(0, 1000);
    
    try testing.expect(player.canAct());
    
    player.fold();
    try testing.expect(!player.is_active);
    try testing.expect(!player.canAct());
}

test "hand initialization" {
    const hand = poker_ai.game_state.Hand.init(0, 1);
    try testing.expectEqual(@as(u8, 0), hand.cards[0]);
    try testing.expectEqual(@as(u8, 1), hand.cards[1]);
    try testing.expect(!hand.isEmpty());
    
    // Empty hand
    const empty_hand = poker_ai.game_state.Hand{ .cards = .{ 255, 255 } };
    try testing.expect(empty_hand.isEmpty());
}

test "action creation and properties" {
    const fold_action = poker_ai.game_state.Action.fold();
    try testing.expectEqual(poker_ai.game_state.ActionType.fold, fold_action.action_type);
    try testing.expectEqual(@as(u32, 0), fold_action.amount);
    try testing.expect(!fold_action.isAgressive());
    
    const call_action = poker_ai.game_state.Action.call();
    try testing.expectEqual(poker_ai.game_state.ActionType.call, call_action.action_type);
    try testing.expect(!call_action.isAgressive());
    
    const check_action = poker_ai.game_state.Action.check();
    try testing.expectEqual(poker_ai.game_state.ActionType.check, check_action.action_type);
    try testing.expect(!check_action.isAgressive());
    
    const raise_action = poker_ai.game_state.Action.raise(100);
    try testing.expectEqual(poker_ai.game_state.ActionType.raise, raise_action.action_type);
    try testing.expectEqual(@as(u32, 100), raise_action.amount);
    try testing.expect(raise_action.isAgressive());
    
    const all_in_action = poker_ai.game_state.Action.allIn(500);
    try testing.expectEqual(poker_ai.game_state.ActionType.all_in, all_in_action.action_type);
    try testing.expectEqual(@as(u32, 500), all_in_action.amount);
    try testing.expect(all_in_action.isAgressive());
}

test "round progression" {
    try testing.expectEqual(poker_ai.game_state.Round.flop, poker_ai.game_state.Round.preflop.next().?);
    try testing.expectEqual(poker_ai.game_state.Round.turn, poker_ai.game_state.Round.flop.next().?);
    try testing.expectEqual(poker_ai.game_state.Round.river, poker_ai.game_state.Round.turn.next().?);
    try testing.expectEqual(@as(?poker_ai.game_state.Round, null), poker_ai.game_state.Round.river.next());
    
    // Test board sizes
    try testing.expectEqual(@as(u8, 0), poker_ai.game_state.Round.preflop.boardSize());
    try testing.expectEqual(@as(u8, 3), poker_ai.game_state.Round.flop.boardSize());
    try testing.expectEqual(@as(u8, 4), poker_ai.game_state.Round.turn.boardSize());
    try testing.expectEqual(@as(u8, 5), poker_ai.game_state.Round.river.boardSize());
}

test "game state initialization" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 3, 5, 10);
    defer game.deinit();
    
    try testing.expectEqual(@as(u8, 3), game.num_players);
    try testing.expectEqual(@as(u8, 3), game.active_players);
    try testing.expectEqual(poker_ai.game_state.Round.preflop, game.round);
    try testing.expectEqual(@as(u32, 5), game.small_blind);
    try testing.expectEqual(@as(u32, 10), game.big_blind);
    try testing.expectEqual(@as(u32, 0), game.pot);
    try testing.expectEqual(@as(u32, 0), game.current_bet);
    try testing.expectEqual(@as(u8, 0), game.current_player);
    try testing.expectEqual(@as(u8, 0), game.dealer_button);
    
    // Check player initialization
    for (game.players[0..game.num_players], 0..) |player, i| {
        try testing.expectEqual(@as(u8, @intCast(i)), player.id);
        try testing.expect(player.is_active);
        try testing.expect(player.hand.isEmpty());
    }
}

test "dealing hole cards" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    const hands = [2][2]u8{
        .{ 0, 1 },   // Player 0: 2c 2d
        .{ 2, 3 },   // Player 1: 2h 2s
    };
    
    game.dealHoleCards(hands[0..]);
    
    try testing.expectEqual(@as(u8, 0), game.players[0].hand.cards[0]);
    try testing.expectEqual(@as(u8, 1), game.players[0].hand.cards[1]);
    try testing.expectEqual(@as(u8, 2), game.players[1].hand.cards[0]);
    try testing.expectEqual(@as(u8, 3), game.players[1].hand.cards[1]);
}

test "dealing board cards" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // Initially no board cards
    try testing.expectEqual(@as(u8, 0), game.board_size);
    
    // Deal flop
    game.round = .flop;
    const flop_cards = [_]u8{ 4, 5, 6 };
    game.dealBoard(flop_cards[0..]);
    
    try testing.expectEqual(@as(u8, 3), game.board_size);
    try testing.expectEqual(@as(u8, 4), game.board[0]);
    try testing.expectEqual(@as(u8, 5), game.board[1]);
    try testing.expectEqual(@as(u8, 6), game.board[2]);
    
    // Deal turn
    game.round = .turn;
    const turn_cards = [_]u8{7};
    game.dealBoard(turn_cards[0..]);
    
    try testing.expectEqual(@as(u8, 4), game.board_size);
    try testing.expectEqual(@as(u8, 7), game.board[3]);
    
    // Deal river
    game.round = .river;
    const river_cards = [_]u8{8};
    game.dealBoard(&river_cards);
    
    try testing.expectEqual(@as(u8, 5), game.board_size);
    try testing.expectEqual(@as(u8, 8), game.board[4]);
}

test "basic action application" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // Test call action
    const call_action = poker_ai.game_state.Action.call();
    const success = try game.applyAction(call_action);
    try testing.expect(success);
    
    // Check that action was recorded
    try testing.expectEqual(@as(usize, 1), game.actions.items.len);
    try testing.expectEqual(@as(usize, 1), game.action_sequence.items.len);
    
    const recorded_action = game.actions.items[0];
    try testing.expectEqual(poker_ai.game_state.ActionType.call, recorded_action.action_type);
}

test "folding mechanics" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 3, 5, 10);
    defer game.deinit();
    
    const initial_active = game.active_players;
    
    // Player folds
    const fold_action = poker_ai.game_state.Action.fold();
    const success = try game.applyAction(fold_action);
    try testing.expect(success);
    
    // Check that active player count decreased
    try testing.expectEqual(initial_active - 1, game.active_players);
    try testing.expect(!game.players[0].is_active);
}

test "betting mechanics" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // Test raise action
    const raise_action = poker_ai.game_state.Action.raise(20);
    const success = try game.applyAction(raise_action);
    try testing.expect(success);
    
    // Check pot and betting state
    try testing.expect(game.pot > 0);
    try testing.expectEqual(@as(u32, 20), game.current_bet);
    try testing.expectEqual(@as(?u8, 0), game.last_raiser);
}

test "invalid actions" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // Make player inactive
    game.players[0].fold();
    
    // Try to apply action for inactive player
    const call_action = poker_ai.game_state.Action.call();
    const success = try game.applyAction(call_action);
    try testing.expect(!success);
}

test "betting round completion" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // With no outstanding bets the round counts as complete
    try testing.expect(game.isBettingComplete());
    
    // Create a mismatch to force an incomplete round
    game.current_bet = 20;
    game.players[0].bet_this_round = 20;
    game.players[1].bet_this_round = 10;
    try testing.expect(!game.isBettingComplete());
    
    // Once the trailing player matches the bet the round is complete again
    game.players[1].bet_this_round = 20;
    try testing.expect(game.isBettingComplete());
}

test "round advancement" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    try testing.expectEqual(poker_ai.game_state.Round.preflop, game.round);
    
    // Advance to next round
    game.nextRound();
    try testing.expectEqual(poker_ai.game_state.Round.flop, game.round);
    
    // Check that betting state was reset
    try testing.expectEqual(@as(u32, 0), game.current_bet);
    try testing.expectEqual(@as(?u8, null), game.last_raiser);
    
    for (game.players[0..game.num_players]) |player| {
        try testing.expectEqual(@as(u32, 0), player.bet_this_round);
    }
}

test "terminal game states" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 3, 5, 10);
    defer game.deinit();
    
    // Initially not terminal
    try testing.expect(!game.isTerminal());
    
    // Make all but one player fold
    game.players[0].fold();
    game.players[1].fold();
    game.active_players = 1;
    
    // Should be terminal
    try testing.expect(game.isTerminal());
    
    // Test river completion
    var game2 = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game2.deinit();
    
    game2.round = .river;
    game2.players[0].bet_this_round = 10;
    game2.players[1].bet_this_round = 10;
    game2.current_bet = 10;
    
    // Should be terminal at river with betting complete
    try testing.expect(game2.isTerminal());
}

test "information set generation" {
    const allocator = testing.allocator;
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // Set up some game state
    game.players[0].hand = poker_ai.game_state.Hand.init(0, 1);
    try game.action_sequence.append(allocator, @intFromEnum(poker_ai.game_state.ActionType.call));
    try game.action_sequence.append(allocator, @intFromEnum(poker_ai.game_state.ActionType.raise));
    
    // Generate info set
    const info_set = try game.getInfoSet(0);
    defer testing.allocator.free(info_set);
    
    // Should contain hole cards + action sequence
    try testing.expect(info_set.len >= 4); // 2 hole cards + at least 2 actions
    try testing.expectEqual(@as(u8, 0), info_set[0]); // First hole card
    try testing.expectEqual(@as(u8, 1), info_set[1]); // Second hole card
}

test "player advancement" {
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 3, 5, 10);
    defer game.deinit();
    
    try testing.expectEqual(@as(u8, 0), game.current_player);
    
    // Advance to next player
    game.advanceToNextPlayer();
    try testing.expectEqual(@as(u8, 1), game.current_player);
    
    // Make player 2 inactive and advance
    game.players[2].fold();
    game.current_player = 1;
    game.advanceToNextPlayer();
    
    // Should skip inactive player 2 and go to player 0
    try testing.expectEqual(@as(u8, 0), game.current_player);
}

test "edge cases and stress testing" {
    const allocator = testing.allocator;
    // Single player game (edge case)
    var single_game = try poker_ai.game_state.GameState.init(testing.allocator, 1, 5, 10);
    defer single_game.deinit();
    
    try testing.expectEqual(@as(u8, 1), single_game.num_players);
    try testing.expect(single_game.isBettingComplete()); // Single player = betting complete
    
    // Maximum players
    var max_game = try poker_ai.game_state.GameState.init(testing.allocator, 6, 5, 10);
    defer max_game.deinit();
    
    try testing.expectEqual(@as(u8, 6), max_game.num_players);
    
    // Test with many actions
    var action_game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer action_game.deinit();
    
    // Add many actions
    for (0..100) |_| {
        try action_game.action_sequence.append(allocator, @intFromEnum(poker_ai.game_state.ActionType.call));
    }
    
    try testing.expectEqual(@as(usize, 100), action_game.action_sequence.items.len);
}
