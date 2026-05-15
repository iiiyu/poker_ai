// Comprehensive tests for CFR algorithm implementation

const std = @import("std");
const testing = std.testing;
const poker_ai = @import("poker_ai");

test "cfr config initialization" {
    const config = poker_ai.cfr.CFRConfig.default();
    
    try testing.expectEqual(@as(u32, 1000), config.iterations);
    try testing.expectEqual(@as(f64, 0.6), config.exploration_probability);
    try testing.expectEqual(@as(f64, -300.0), config.prune_threshold);
    try testing.expectEqual(@as(f64, 1.5), config.discount_alpha);
    try testing.expectEqual(@as(f64, 0.0), config.discount_beta);
}

test "cfr config custom values" {
    const config = poker_ai.cfr.CFRConfig{
        .iterations = 500,
        .exploration_probability = 0.3,
        .prune_threshold = -100.0,
        .discount_alpha = 2.0,
        .discount_beta = 0.5,
    };
    
    try testing.expectEqual(@as(u32, 500), config.iterations);
    try testing.expectEqual(@as(f64, 0.3), config.exploration_probability);
    try testing.expectEqual(@as(f64, -100.0), config.prune_threshold);
    try testing.expectEqual(@as(f64, 2.0), config.discount_alpha);
    try testing.expectEqual(@as(f64, 0.5), config.discount_beta);
}

test "info set node creation and initialization" {
    const info_set = "test_info_set";
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, info_set, 3);
    defer node.deinit();
    
    try testing.expectEqual(@as(u8, 3), node.num_actions);
    try testing.expectEqualStrings(info_set, node.info_set);
    try testing.expectEqual(@as(f64, 1.0), node.reach_probability);
    
    // Check that arrays are properly allocated and initialized
    try testing.expectEqual(@as(usize, 3), node.regret_sum.len);
    try testing.expectEqual(@as(usize, 3), node.strategy_sum.len);
    
    // Should be initialized to zero
    for (node.regret_sum) |regret| {
        try testing.expectApproxEqAbs(@as(f64, 0.0), regret, 1e-9);
    }
    for (node.strategy_sum) |sum| {
        try testing.expectApproxEqAbs(@as(f64, 0.0), sum, 1e-9);
    }
}

test "info set node strategy calculation" {
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, "test", 3);
    defer node.deinit();
    
    // Set some regret values
    node.regret_sum[0] = 10.0;
    node.regret_sum[1] = 5.0;
    node.regret_sum[2] = -2.0; // Negative regret
    
    const strategy = try node.getStrategy(1.0);
    defer testing.allocator.free(strategy);
    
    // Check that strategy is valid probability distribution
    var sum: f64 = 0.0;
    for (strategy) |prob| {
        try testing.expect(prob >= 0.0);
        try testing.expect(prob <= 1.0);
        sum += prob;
    }
    try testing.expectApproxEqAbs(@as(f64, 1.0), sum, 0.001);
    
    // Positive regrets should get higher probability
    try testing.expect(strategy[0] > strategy[1]);
    try testing.expect(strategy[1] > strategy[2]);
}

test "info set node uniform strategy on zero regrets" {
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, "test", 4);
    defer node.deinit();
    
    // All regrets are zero (initial state)
    const strategy = try node.getStrategy(1.0);
    defer testing.allocator.free(strategy);
    
    // Should get uniform distribution
    const expected_prob = 1.0 / 4.0;
    for (strategy) |prob| {
        try testing.expectApproxEqAbs(expected_prob, prob, 0.001);
    }
}

test "info set node average strategy calculation" {
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, "test", 2);
    defer node.deinit();
    
    // Simulate some strategy updates
    node.strategy_sum[0] = 30.0;
    node.strategy_sum[1] = 20.0;
    
    const avg_strategy = try node.getAverageStrategy();
    defer testing.allocator.free(avg_strategy);
    
    try testing.expectApproxEqAbs(@as(f64, 0.6), avg_strategy[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.4), avg_strategy[1], 0.001);
}

test "mccfr trainer initialization" {
    // Create required dependencies
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(testing.allocator);
    defer strategy_table.deinit();
    
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(testing.allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    
    const config = poker_ai.cfr.CFRConfig{
        .iterations = 10,
        .exploration_probability = 0.5,
        .prune_threshold = -200.0,
        .discount_alpha = 1.0,
        .discount_beta = 0.0,
    };
    
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        testing.allocator,
        config,
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    try testing.expectEqual(@as(u32, 10), trainer.config.iterations);
    try testing.expectEqual(@as(u32, 0), trainer.iteration);
    try testing.expectEqual(@as(usize, 0), trainer.nodes.count());
}

test "mccfr trainer node management" {
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(testing.allocator);
    defer strategy_table.deinit();
    
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(testing.allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        testing.allocator,
        poker_ai.cfr.CFRConfig.default(),
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    // Test getting or creating nodes
    const info_set = "test_info_set";
    const node1 = try trainer.getOrCreateNode(12345, info_set, 3);
    const node2 = try trainer.getOrCreateNode(12345, info_set, 3);
    
    // Should return the same node
    try testing.expectEqual(node1, node2);
    try testing.expectEqual(@as(usize, 1), trainer.nodes.count());
    
    // Different hash should create new node
    const node3 = try trainer.getOrCreateNode(54321, "different", 2);
    try testing.expect(node1 != node3);
    try testing.expectEqual(@as(usize, 2), trainer.nodes.count());
}

test "mccfr random game creation" {
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(testing.allocator);
    defer strategy_table.deinit();
    
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(testing.allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        testing.allocator,
        poker_ai.cfr.CFRConfig.default(),
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    var game = try trainer.createRandomGame();
    defer game.deinit();
    
    try testing.expectEqual(@as(u8, 2), game.num_players);
    try testing.expectEqual(@as(u32, 5), game.small_blind);
    try testing.expectEqual(@as(u32, 10), game.big_blind);
    
    // Players should have random hole cards
    try testing.expect(!game.players[0].hand.isEmpty());
    try testing.expect(!game.players[1].hand.isEmpty());
    
    // Cards should be different
    const p0_cards = game.players[0].hand.cards;
    const p1_cards = game.players[1].hand.cards;
    try testing.expect(p0_cards[0] != p1_cards[0] or p0_cards[1] != p1_cards[1]);
}

test "mccfr game state cloning" {
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(testing.allocator);
    defer strategy_table.deinit();
    
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(testing.allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        testing.allocator,
        poker_ai.cfr.CFRConfig.default(),
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    // Create original game
    var original = try poker_ai.game_state.GameState.init(testing.allocator, 2, 10, 20);
    defer original.deinit();
    
    original.pot = 100;
    original.current_bet = 50;
    try original.action_sequence.append(testing.allocator, 1);
    try original.action_sequence.append(testing.allocator, 2);
    
    // Clone the game
    var clone = try trainer.cloneGameState(&original);
    defer clone.deinit();
    
    // Check that clone has same state
    try testing.expectEqual(original.num_players, clone.num_players);
    try testing.expectEqual(original.pot, clone.pot);
    try testing.expectEqual(original.current_bet, clone.current_bet);
    try testing.expectEqual(original.action_sequence.items.len, clone.action_sequence.items.len);
    
    // Modify original to ensure deep copy
    original.pot = 200;
    try testing.expectEqual(@as(u32, 100), clone.pot); // Clone should be unaffected
}

test "mccfr available actions generation" {
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(testing.allocator);
    defer strategy_table.deinit();
    
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(testing.allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        testing.allocator,
        poker_ai.cfr.CFRConfig.default(),
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    const actions = try trainer.getAvailableActions(&game);
    defer testing.allocator.free(actions);
    
    // Should have at least fold and check/call
    try testing.expect(actions.len >= 2);
    
    // First action should always be fold
    try testing.expectEqual(poker_ai.game_state.ActionType.fold, actions[0].action_type);
    
    // Should have either check or call
    var has_check_or_call = false;
    for (actions) |action| {
        if (action.action_type == .check or action.action_type == .call) {
            has_check_or_call = true;
            break;
        }
    }
    try testing.expect(has_check_or_call);
}

test "mccfr utility calculation" {
    var strategy_table = poker_ai.strategy_table.StrategyTable.init(testing.allocator);
    defer strategy_table.deinit();
    
    var abstraction_table = try poker_ai.lookup_tables.AbstractionTable.init(testing.allocator);
    defer abstraction_table.deinit();
    
    var hand_evaluator = poker_ai.hand_eval.HandEvaluator.init();
    
    var trainer = try poker_ai.cfr.MCCFRTrainer.init(
        testing.allocator,
        poker_ai.cfr.CFRConfig.default(),
        &strategy_table,
        &abstraction_table,
        &hand_evaluator,
    );
    defer trainer.deinit();
    
    var game = try poker_ai.game_state.GameState.init(testing.allocator, 2, 5, 10);
    defer game.deinit();
    
    // Set up terminal state with one player folded
    game.players[0].fold();
    game.active_players = 1;
    game.pot = 100;
    game.players[1].total_bet = 50;
    
    // Player 1 should win the pot
    const utility1 = trainer.getUtility(&game, 1);
    try testing.expectApproxEqAbs(@as(f64, 100.0), utility1, 1e-9);
    
    // Player 0 should lose their bet
    const utility0 = trainer.getUtility(&game, 0);
    try testing.expect(utility0 <= 0.0);
}

test "mccfr small training run" {
    return error.SkipZigTest;
}

test "regret matching edge cases" {
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, "test", 3);
    defer node.deinit();
    
    // All negative regrets
    node.regret_sum[0] = -10.0;
    node.regret_sum[1] = -5.0;
    node.regret_sum[2] = -15.0;
    
    const strategy = try node.getStrategy(1.0);
    defer testing.allocator.free(strategy);
    
    // Should get uniform distribution
    for (strategy) |prob| {
        try testing.expectApproxEqAbs(@as(f64, 1.0/3.0), prob, 0.001);
    }
}

test "strategy accumulation" {
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, "test", 2);
    defer node.deinit();
    
    // First strategy update
    node.regret_sum[0] = 5.0;
    node.regret_sum[1] = 3.0;
    
    const strategy1 = try node.getStrategy(2.0); // weight = 2.0
    defer testing.allocator.free(strategy1);
    
    // Second strategy update
    node.regret_sum[0] = 3.0;
    node.regret_sum[1] = 5.0;
    
    const strategy2 = try node.getStrategy(1.0); // weight = 1.0
    defer testing.allocator.free(strategy2);
    
    // Check that strategy sums accumulated
    try testing.expect(node.strategy_sum[0] > 0);
    try testing.expect(node.strategy_sum[1] > 0);
    
    const avg_strategy = try node.getAverageStrategy();
    defer testing.allocator.free(avg_strategy);
    
    // Average should be weighted properly
    var sum: f64 = 0;
    for (avg_strategy) |prob| {
        sum += prob;
    }
    try testing.expectApproxEqAbs(@as(f64, 1.0), sum, 0.001);
}

test "large regret values handling" {
    var node = try poker_ai.cfr.InfoSetNode.init(testing.allocator, "test", 2);
    defer node.deinit();
    
    // Very large regret values
    node.regret_sum[0] = 1e10;
    node.regret_sum[1] = 1e5;
    
    const strategy = try node.getStrategy(1.0);
    defer testing.allocator.free(strategy);
    
    // Should not overflow and should be valid probabilities
    var sum: f64 = 0;
    for (strategy) |prob| {
        try testing.expect(prob >= 0.0);
        try testing.expect(prob <= 1.0);
        try testing.expect(!std.math.isNan(prob));
        try testing.expect(!std.math.isInf(prob));
        sum += prob;
    }
    try testing.expectApproxEqAbs(@as(f64, 1.0), sum, 0.001);
}

test "memory cleanup verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    {
        var node = try poker_ai.cfr.InfoSetNode.init(allocator, "test_node", 5);
        defer node.deinit();
        
        const strategy = try node.getStrategy(1.0);
        defer allocator.free(strategy);
        
        const avg_strategy = try node.getAverageStrategy();
        defer allocator.free(avg_strategy);
    }
    
    const deinit_status = gpa.deinit();
    try testing.expectEqual(std.heap.Check.ok, deinit_status);
}
