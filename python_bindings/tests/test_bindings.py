"""
Comprehensive tests for Python-Zig bindings.

Tests all aspects of the binding layer including FFI calls,
memory management, error handling, and compatibility with
existing Python code.
"""

import unittest
import tempfile
import os
import time
from pathlib import Path
import numpy as np
from typing import List, Dict, Any

# Import the bindings
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from poker_ai_zig import (
    HandEvaluator, GameState, CFRTrainer, StrategyTable,
    card_from_rank_suit, card_get_rank, card_get_suit,
    get_version, poker_ai_context,
    PokerAIError, InvalidParameterError, AllocationError,
    GameStateError, StrategyError, FileError
)
from game_state_converter import (
    GameStateConverter, ActionType, GamePhase, PythonGameState,
    PlayerState, NumpyArrayConverter, get_converter
)
from strategy_loader import (
    StrategyLoader, StrategyFormat, get_strategy_loader
)
from training_interface import (
    TrainingConfig, ZigTrainingInterface, CompatibilityTrainer,
    TrainingProgress
)

class TestZigLibraryBasics(unittest.TestCase):
    """Test basic Zig library functionality."""
    
    def test_library_version(self):
        """Test that we can get library version."""
        version = get_version()
        self.assertIsInstance(version, tuple)
        self.assertEqual(len(version), 3)
        self.assertTrue(all(isinstance(v, int) for v in version))
    
    def test_context_manager(self):
        """Test the context manager works properly."""
        with poker_ai_context() as lib:
            self.assertIsNotNone(lib)
            version = lib.get_version()
            self.assertIsInstance(version, tuple)

class TestCardUtilities(unittest.TestCase):
    """Test card utility functions."""
    
    def test_card_creation(self):
        """Test card creation from rank and suit."""
        # Test valid cards
        card = card_from_rank_suit(0, 0)  # 2 of spades
        self.assertIsInstance(card, int)
        self.assertGreaterEqual(card, 0)
        self.assertLess(card, 52)
        
        # Test rank extraction
        rank = card_get_rank(card)
        self.assertEqual(rank, 0)
        
        # Test suit extraction
        suit = card_get_suit(card)
        self.assertEqual(suit, 0)
    
    def test_invalid_card_creation(self):
        """Test error handling for invalid cards."""
        with self.assertRaises(InvalidParameterError):
            card_from_rank_suit(13, 0)  # Invalid rank
        
        with self.assertRaises(InvalidParameterError):
            card_from_rank_suit(0, 4)   # Invalid suit

class TestHandEvaluator(unittest.TestCase):
    """Test hand evaluation functionality."""
    
    def setUp(self):
        self.evaluator = HandEvaluator()
    
    def test_hand_evaluator_creation(self):
        """Test that hand evaluator can be created."""
        self.assertIsInstance(self.evaluator, HandEvaluator)
    
    def test_five_card_evaluation(self):
        """Test 5-card hand evaluation."""
        # Royal flush in spades: 10, J, Q, K, A of spades
        cards = [
            card_from_rank_suit(8, 0),   # 10 of spades
            card_from_rank_suit(9, 0),   # J of spades
            card_from_rank_suit(10, 0),  # Q of spades
            card_from_rank_suit(11, 0),  # K of spades
            card_from_rank_suit(12, 0),  # A of spades
        ]
        
        result = self.evaluator.evaluate_5(cards)
        self.assertIsInstance(result, int)
        self.assertGreater(result, 0)
    
    def test_seven_card_evaluation(self):
        """Test 7-card hand evaluation."""
        # Mix of cards that should form a decent hand
        cards = [
            card_from_rank_suit(0, 0),   # 2 of spades
            card_from_rank_suit(1, 0),   # 3 of spades
            card_from_rank_suit(12, 0),  # A of spades
            card_from_rank_suit(11, 1),  # K of hearts
            card_from_rank_suit(10, 2),  # Q of diamonds
            card_from_rank_suit(9, 3),   # J of clubs
            card_from_rank_suit(8, 0),   # 10 of spades
        ]
        
        result = self.evaluator.evaluate_7(cards)
        self.assertIsInstance(result, int)
        self.assertGreater(result, 0)
    
    def test_invalid_hand_sizes(self):
        """Test error handling for invalid hand sizes."""
        with self.assertRaises(InvalidParameterError):
            self.evaluator.evaluate_5([1, 2, 3, 4])  # Too few cards
        
        with self.assertRaises(InvalidParameterError):
            self.evaluator.evaluate_7([1, 2, 3, 4, 5, 6])  # Too few cards

class TestGameState(unittest.TestCase):
    """Test game state functionality."""
    
    def setUp(self):
        self.game = GameState(num_players=4, small_blind=10, big_blind=20)
    
    def test_game_state_creation(self):
        """Test that game state can be created."""
        self.assertIsInstance(self.game, GameState)
    
    def test_invalid_player_count(self):
        """Test error handling for invalid player counts."""
        with self.assertRaises(InvalidParameterError):
            GameState(num_players=1, small_blind=10, big_blind=20)
        
        with self.assertRaises(InvalidParameterError):
            GameState(num_players=7, small_blind=10, big_blind=20)
    
    def test_deal_hole_cards(self):
        """Test dealing hole cards."""
        card1 = card_from_rank_suit(0, 0)
        card2 = card_from_rank_suit(1, 1)
        
        # Should not raise exception
        self.game.deal_hole_cards(0, card1, card2)
    
    def test_apply_action(self):
        """Test applying actions."""
        # Fold action
        result = self.game.apply_action(ActionType.FOLD, 0)
        self.assertTrue(result)
        
        # Call action with amount
        result = self.game.apply_action(ActionType.CALL, 20)
        self.assertTrue(result)
    
    def test_game_properties(self):
        """Test game state properties."""
        # These should not raise exceptions
        pot = self.game.pot
        self.assertIsInstance(pot, int)
        
        current_player = self.game.current_player
        self.assertIsInstance(current_player, int)
        self.assertGreaterEqual(current_player, 0)
        self.assertLess(current_player, 4)
        
        # Terminal check
        is_terminal = self.game.is_terminal()
        self.assertIsInstance(is_terminal, bool)

class TestCFRTrainer(unittest.TestCase):
    """Test CFR training functionality."""
    
    def setUp(self):
        self.trainer = CFRTrainer(iterations=10, num_threads=1)
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_trainer_creation(self):
        """Test that CFR trainer can be created."""
        self.assertIsInstance(self.trainer, CFRTrainer)
    
    def test_strategy_save_load(self):
        """Test saving and loading strategies."""
        strategy_path = os.path.join(self.temp_dir, "test_strategy.zig")
        
        # Save strategy
        self.trainer.save_strategy(strategy_path)
        self.assertTrue(os.path.exists(strategy_path))
        
        # Load strategy
        new_trainer = CFRTrainer(iterations=10, num_threads=1)
        new_trainer.load_strategy(strategy_path)

class TestStrategyTable(unittest.TestCase):
    """Test strategy table functionality."""
    
    def setUp(self):
        self.strategy_table = StrategyTable()
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_strategy_table_creation(self):
        """Test that strategy table can be created."""
        self.assertIsInstance(self.strategy_table, StrategyTable)
    
    def test_memory_usage(self):
        """Test memory usage reporting."""
        usage = self.strategy_table.memory_usage
        self.assertIsInstance(usage, int)
        self.assertGreaterEqual(usage, 0)
    
    def test_save_load(self):
        """Test saving and loading strategy tables."""
        table_path = os.path.join(self.temp_dir, "test_table.zig")
        
        # Save table
        self.strategy_table.save(table_path)
        self.assertTrue(os.path.exists(table_path))
        
        # Load table
        new_table = StrategyTable()
        new_table.load(table_path)

class TestGameStateConverter(unittest.TestCase):
    """Test game state conversion functionality."""
    
    def setUp(self):
        self.converter = GameStateConverter()
    
    def test_card_conversion(self):
        """Test card conversion between Python and Zig."""
        # Test Python tuple to Zig
        python_card = (12, 'spades')  # Ace of spades
        zig_card = self.converter.card_to_zig(python_card)
        self.assertIsInstance(zig_card, int)
        
        # Test Zig to Python
        converted_back = self.converter.card_from_zig(zig_card)
        self.assertEqual(converted_back, python_card)
    
    def test_action_conversion(self):
        """Test action conversion."""
        # Python action to Zig
        python_action = {'action': 'RAISE', 'amount': 100}
        action_type, amount = self.converter.action_to_zig(python_action)
        self.assertEqual(action_type, ActionType.RAISE)
        self.assertEqual(amount, 100)
        
        # Zig action to Python
        converted_back = self.converter.action_from_zig(action_type, amount)
        self.assertEqual(converted_back['action'], 'raise')
        self.assertEqual(converted_back['amount'], 100)
    
    def test_game_state_conversion(self):
        """Test full game state conversion."""
        # Create a Python game state
        players = [
            PlayerState(
                chips=1000,
                committed=20,
                hole_cards=((12, 'spades'), (11, 'hearts')),
                is_active=True,
                is_folded=False
            ),
            PlayerState(
                chips=2000,
                committed=10,
                hole_cards=((10, 'diamonds'), (9, 'clubs')),
                is_active=True,
                is_folded=False
            ),
        ]
        
        game_state = PythonGameState(
            num_players=2,
            current_player=0,
            dealer_button=1,
            small_blind=10,
            big_blind=20,
            pot=30,
            phase=GamePhase.PREFLOP,
            community_cards=[],
            players=players,
            action_history=[(0, ActionType.RAISE, 20)]
        )
        
        # Convert to Zig format
        zig_data = self.converter.gamestate_to_zig_compatible(game_state)
        self.assertIsInstance(zig_data, dict)
        self.assertEqual(zig_data['num_players'], 2)
        self.assertEqual(zig_data['pot'], 30)
        
        # Convert back to Python
        converted_back = self.converter.gamestate_from_zig_compatible(zig_data)
        self.assertEqual(converted_back.num_players, game_state.num_players)
        self.assertEqual(converted_back.pot, game_state.pot)
        self.assertEqual(converted_back.phase, game_state.phase)

class TestNumpyArrayConverter(unittest.TestCase):
    """Test numpy array conversion."""
    
    def test_array_conversion(self):
        """Test numpy array conversion for Zig transfer."""
        # Create test array
        original_array = np.array([[1.0, 2.0], [3.0, 4.0]], dtype=np.float32)
        
        # Prepare for Zig
        dtype_code, total_size, data_bytes = NumpyArrayConverter.prepare_for_zig(original_array)
        
        self.assertIsInstance(dtype_code, int)
        self.assertIsInstance(total_size, int)
        self.assertIsInstance(data_bytes, bytes)
        self.assertEqual(total_size, 4)
        
        # Restore from Zig
        restored_array = NumpyArrayConverter.restore_from_zig(
            dtype_code, original_array.shape, data_bytes
        )
        
        np.testing.assert_array_equal(original_array, restored_array)

class TestStrategyLoader(unittest.TestCase):
    """Test strategy loading and conversion."""
    
    def setUp(self):
        self.loader = get_strategy_loader()
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_format_detection(self):
        """Test strategy format detection."""
        # Create test files
        json_file = os.path.join(self.temp_dir, "test.json")
        with open(json_file, 'w') as f:
            f.write('{"test": true}')
        
        format = self.loader.detect_format(json_file)
        self.assertEqual(format, StrategyFormat.JSON)
    
    def test_json_strategy_handling(self):
        """Test JSON strategy loading and saving."""
        test_strategy = {
            'version': '1.0',
            'data': [1, 2, 3, 4],
            'metadata': {'created': 'test'}
        }
        
        json_file = os.path.join(self.temp_dir, "test_strategy.json")
        
        # Save
        self.loader.save_python_strategy(test_strategy, json_file, StrategyFormat.JSON)
        self.assertTrue(os.path.exists(json_file))
        
        # Load
        loaded_strategy = self.loader.load_python_strategy(json_file, StrategyFormat.JSON)
        self.assertEqual(loaded_strategy, test_strategy)

class TestTrainingInterface(unittest.TestCase):
    """Test training interface functionality."""
    
    def setUp(self):
        self.config = TrainingConfig(
            iterations=10,
            num_threads=1,
            checkpoint_interval=5,
            save_interval=5,
            log_interval=2
        )
        self.interface = ZigTrainingInterface(self.config)
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_config_creation(self):
        """Test training config creation."""
        self.assertEqual(self.config.iterations, 10)
        self.assertEqual(self.config.num_threads, 1)
    
    def test_trainer_creation(self):
        """Test CFR trainer creation through interface."""
        trainer = self.interface.create_trainer()
        self.assertIsInstance(trainer, CFRTrainer)
    
    def test_compatibility_trainer(self):
        """Test compatibility trainer with Python-style config."""
        python_config = {
            'iterations': 5,
            'n_jobs': 1,
            'verbose': False,
            'save_path': os.path.join(self.temp_dir, 'compat_strategy.zig')
        }
        
        compat_trainer = CompatibilityTrainer(python_config)
        self.assertIsInstance(compat_trainer, CompatibilityTrainer)
        
        # Test training (should complete quickly with 5 iterations)
        result = compat_trainer.train(show_progress=False)
        self.assertIsInstance(result, dict)
        self.assertIn('success', result)
        self.assertEqual(result['iterations_completed'], 5)

class TestErrorHandling(unittest.TestCase):
    """Test error handling across the binding layer."""
    
    def test_invalid_parameters(self):
        """Test that invalid parameters raise appropriate errors."""
        with self.assertRaises(InvalidParameterError):
            GameState(num_players=0, small_blind=10, big_blind=20)
    
    def test_file_errors(self):
        """Test file operation error handling."""
        strategy_table = StrategyTable()
        
        with self.assertRaises(FileError):
            strategy_table.load("/nonexistent/path/strategy.zig")

class TestMemoryManagement(unittest.TestCase):
    """Test memory management and cleanup."""
    
    def test_object_cleanup(self):
        """Test that objects are properly cleaned up."""
        # Create many objects to test memory management
        evaluators = []
        for i in range(10):
            evaluator = HandEvaluator()
            evaluators.append(evaluator)
        
        # Delete references
        del evaluators
        
        # Force garbage collection
        import gc
        gc.collect()
        
        # Test should complete without memory errors

class TestPerformance(unittest.TestCase):
    """Basic performance tests."""
    
    def test_hand_evaluation_speed(self):
        """Test hand evaluation performance."""
        evaluator = HandEvaluator()
        
        # Create test hands
        hands = []
        for i in range(100):
            hand = [
                card_from_rank_suit(i % 13, 0),
                card_from_rank_suit((i + 1) % 13, 1),
                card_from_rank_suit((i + 2) % 13, 2),
                card_from_rank_suit((i + 3) % 13, 3),
                card_from_rank_suit((i + 4) % 13, 0),
            ]
            hands.append(hand)
        
        # Time evaluation
        start_time = time.time()
        for hand in hands:
            evaluator.evaluate_5(hand)
        end_time = time.time()
        
        total_time = end_time - start_time
        evaluations_per_second = len(hands) / total_time
        
        # Should be reasonably fast (at least 1000 evaluations/second)
        self.assertGreater(evaluations_per_second, 1000)

if __name__ == '__main__':
    # Run tests with detailed output
    unittest.main(verbosity=2)