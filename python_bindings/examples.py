#!/usr/bin/env python3
"""
Example usage of Python bindings for Zig poker AI.

This script demonstrates the key features of the binding layer,
including hand evaluation, game state management, training,
and strategy conversion.
"""

import os
import time
import tempfile
import asyncio
from pathlib import Path

# Add parent directory to path for imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from poker_ai.python_bindings import (
        # Core functionality
        HandEvaluator, GameState, CFRTrainer, StrategyTable,
        
        # Utility functions
        card_from_rank_suit, card_get_rank, card_get_suit, get_version,
        poker_ai_context,
        
        # Training
        TrainingConfig, ZigTrainingInterface, CompatibilityTrainer,
        
        # Conversion
        get_converter, ActionType, GamePhase, PythonGameState, PlayerState,
        
        # Strategy management
        get_strategy_loader, StrategyFormat,
        
        # Error handling
        PokerAIError, InvalidParameterError,
    )
    BINDINGS_AVAILABLE = True
except ImportError as e:
    print(f"Warning: Could not import bindings: {e}")
    print("Make sure the Zig library is built and available.")
    BINDINGS_AVAILABLE = False

def example_library_info():
    """Demonstrate getting library information."""
    print("=== Library Information ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        version = get_version()
        print(f"Zig library version: {version[0]}.{version[1]}.{version[2]}")
        
        # Test compatibility
        from poker_ai.python_bindings import check_compatibility
        compat = check_compatibility()
        print(f"Compatibility status: {compat['status']}")
        if compat['status'] == 'compatible':
            print(f"Test evaluation result: {compat['test_result']}")
        else:
            print(f"Compatibility issue: {compat['message']}")
            
    except Exception as e:
        print(f"Error getting library info: {e}")

def example_hand_evaluation():
    """Demonstrate hand evaluation functionality."""
    print("\n=== Hand Evaluation Example ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        with poker_ai_context():
            evaluator = HandEvaluator()
            
            # Create some example hands
            hands = {
                "Royal Flush": [
                    card_from_rank_suit(8, 0),   # 10 of spades
                    card_from_rank_suit(9, 0),   # J of spades
                    card_from_rank_suit(10, 0),  # Q of spades  
                    card_from_rank_suit(11, 0),  # K of spades
                    card_from_rank_suit(12, 0),  # A of spades
                ],
                "Four of a Kind": [
                    card_from_rank_suit(12, 0),  # A of spades
                    card_from_rank_suit(12, 1),  # A of hearts
                    card_from_rank_suit(12, 2),  # A of diamonds
                    card_from_rank_suit(12, 3),  # A of clubs
                    card_from_rank_suit(11, 0),  # K of spades
                ],
                "High Card": [
                    card_from_rank_suit(2, 0),   # 4 of spades
                    card_from_rank_suit(5, 1),   # 7 of hearts
                    card_from_rank_suit(8, 2),   # 10 of diamonds
                    card_from_rank_suit(9, 3),   # J of clubs
                    card_from_rank_suit(12, 0),  # A of spades
                ],
            }
            
            print("Hand evaluations (higher score = better hand):")
            for hand_name, cards in hands.items():
                score = evaluator.evaluate_5(cards)
                print(f"  {hand_name:15}: {score:8}")
                
                # Show individual cards
                card_strs = []
                for card in cards:
                    rank = card_get_rank(card)
                    suit = card_get_suit(card)
                    rank_name = ['2','3','4','5','6','7','8','9','T','J','Q','K','A'][rank]
                    suit_name = ['♠','♥','♦','♣'][suit]
                    card_strs.append(f"{rank_name}{suit_name}")
                print(f"    Cards: {' '.join(card_strs)}")
            
    except Exception as e:
        print(f"Error in hand evaluation: {e}")

def example_game_state():
    """Demonstrate game state management."""
    print("\n=== Game State Example ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        with poker_ai_context():
            # Create a 4-player game
            game = GameState(num_players=4, small_blind=10, big_blind=20)
            print(f"Created game: {game.pot} pot, player {game.current_player} to act")
            
            # Deal hole cards
            game.deal_hole_cards(0, card_from_rank_suit(12, 0), card_from_rank_suit(12, 1))  # AA
            game.deal_hole_cards(1, card_from_rank_suit(11, 2), card_from_rank_suit(11, 3))  # KK
            print("Dealt hole cards to players 0 and 1")
            
            # Simulate some actions
            actions = [
                (ActionType.RAISE, 60, "Player 0 raises to 60"),
                (ActionType.CALL, 60, "Player 1 calls"),
                (ActionType.FOLD, 0, "Player 2 folds"),
                (ActionType.FOLD, 0, "Player 3 folds"),
            ]
            
            for action_type, amount, description in actions:
                if not game.is_terminal():
                    game.apply_action(action_type, amount)
                    print(f"{description} - Pot: {game.pot}, Current player: {game.current_player}")
                else:
                    print("Game is terminal, no more actions possible")
                    break
            
            print(f"Final state: Terminal={game.is_terminal()}, Pot={game.pot}")
            
    except Exception as e:
        print(f"Error in game state example: {e}")

def example_training_sync():
    """Demonstrate synchronous training."""
    print("\n=== Synchronous Training Example ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        # Use a small number of iterations for demo
        config = TrainingConfig(
            iterations=50,
            num_threads=1,
            checkpoint_interval=20,
            save_interval=25,
            log_interval=10,
            enable_logging=True
        )
        
        trainer = ZigTrainingInterface(config)
        
        # Progress callback
        def progress_callback(progress):
            if progress.current_iteration % 10 == 0:
                print(f"  Progress: {progress.current_iteration}/{progress.total_iterations} "
                      f"({progress.iterations_per_second:.1f} it/s)")
        
        print(f"Starting training with {config.iterations} iterations...")
        start_time = time.time()
        
        result = trainer.train_sync(progress_callback)
        
        end_time = time.time()
        print(f"Training completed in {end_time - start_time:.2f} seconds")
        print(f"Final iteration: {result.current_iteration}")
        print(f"Average speed: {result.iterations_per_second:.1f} iterations/second")
        
        # Save strategy to temp file
        with tempfile.NamedTemporaryFile(suffix='.zig', delete=False) as tmp:
            trainer.save_strategy(tmp.name)
            print(f"Strategy saved to: {tmp.name}")
            
            # Clean up
            os.unlink(tmp.name)
        
    except Exception as e:
        print(f"Error in training example: {e}")

async def example_training_async():
    """Demonstrate asynchronous training."""
    print("\n=== Asynchronous Training Example ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        config = TrainingConfig(
            iterations=30,
            num_threads=1,
            log_interval=10
        )
        
        trainer = ZigTrainingInterface(config)
        
        print(f"Starting async training with {config.iterations} iterations...")
        start_time = time.time()
        
        # Progress monitoring task
        async def monitor_progress():
            while trainer.monitor.progress.is_running:
                progress = trainer.monitor.progress
                if progress.current_iteration > 0:
                    print(f"  Async progress: {progress.current_iteration}/{progress.total_iterations}")
                await asyncio.sleep(1.0)
        
        # Run training and monitoring concurrently
        training_task = trainer.train_async()
        monitoring_task = monitor_progress()
        
        # Wait for training to complete
        result, _ = await asyncio.gather(training_task, monitoring_task, return_exceptions=True)
        
        end_time = time.time()
        print(f"Async training completed in {end_time - start_time:.2f} seconds")
        print(f"Final iteration: {result.current_iteration}")
        
    except Exception as e:
        print(f"Error in async training example: {e}")

def example_compatibility_trainer():
    """Demonstrate compatibility with existing Python code."""
    print("\n=== Compatibility Trainer Example ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        # Python-style configuration (like existing codebase)
        config = {
            'iterations': 25,
            'n_jobs': 1,
            'verbose': True,
            'checkpoint_every': 10,
            'save_every': 15
        }
        
        print("Creating compatibility trainer with Python-style config...")
        trainer = CompatibilityTrainer(config)
        
        print("Training with Python-compatible interface...")
        result = trainer.train(show_progress=True)
        
        print(f"\nTraining result:")
        print(f"  Success: {result['success']}")
        print(f"  Iterations: {result['iterations_completed']}")
        print(f"  Time: {result['total_time']:.2f} seconds")
        print(f"  Speed: {result['iterations_per_second']:.1f} it/s")
        
        # Save in Python format
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            trainer.save(tmp.name, format=StrategyFormat.JSON)
            print(f"Strategy saved in JSON format: {tmp.name}")
            
            # Clean up
            os.unlink(tmp.name)
        
    except Exception as e:
        print(f"Error in compatibility trainer example: {e}")

def example_game_state_conversion():
    """Demonstrate game state conversion between Python and Zig."""
    print("\n=== Game State Conversion Example ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        converter = get_converter()
        
        # Create Python game state
        players = [
            PlayerState(
                chips=1000,
                committed=20,
                hole_cards=((12, 'spades'), (11, 'hearts')),  # A♠ K♥
                is_active=True,
                is_folded=False
            ),
            PlayerState(
                chips=2000,
                committed=10,
                hole_cards=((10, 'diamonds'), (9, 'clubs')),  # Q♦ J♣  
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
        
        print("Original Python game state:")
        print(f"  Players: {game_state.num_players}")
        print(f"  Pot: {game_state.pot}")
        print(f"  Phase: {game_state.phase.name}")
        print(f"  Current player: {game_state.current_player}")
        
        # Convert to Zig format
        zig_data = converter.gamestate_to_zig_compatible(game_state)
        print(f"\nConverted to Zig format: {len(zig_data)} fields")
        
        # Convert back to Python
        restored_state = converter.gamestate_from_zig_compatible(zig_data)
        print(f"\nRestored Python game state:")
        print(f"  Players: {restored_state.num_players}")
        print(f"  Pot: {restored_state.pot}")
        print(f"  Phase: {restored_state.phase.name}")
        print(f"  Current player: {restored_state.current_player}")
        
        # Verify conversion is correct
        assert game_state.num_players == restored_state.num_players
        assert game_state.pot == restored_state.pot
        assert game_state.phase == restored_state.phase
        print("✓ Conversion successful - all fields match")
        
    except Exception as e:
        print(f"Error in game state conversion example: {e}")

def example_performance_comparison():
    """Demonstrate performance comparison."""
    print("\n=== Performance Comparison ===")
    
    if not BINDINGS_AVAILABLE:
        print("Bindings not available - skipping example")
        return
    
    try:
        with poker_ai_context():
            evaluator = HandEvaluator()
            
            # Generate test hands
            num_hands = 1000
            hands = []
            for i in range(num_hands):
                hand = [
                    i % 52,
                    (i + 1) % 52,
                    (i + 2) % 52,
                    (i + 3) % 52,
                    (i + 4) % 52
                ]
                hands.append(hand)
            
            print(f"Evaluating {num_hands} hands...")
            
            # Time the evaluation
            start_time = time.time()
            for hand in hands:
                score = evaluator.evaluate_5(hand)
            end_time = time.time()
            
            total_time = end_time - start_time
            evaluations_per_second = num_hands / total_time
            
            print(f"Results:")
            print(f"  Total time: {total_time:.3f} seconds")
            print(f"  Speed: {evaluations_per_second:.0f} evaluations/second")
            print(f"  Average per hand: {total_time * 1000 / num_hands:.3f} ms")
            
            # Memory usage estimation
            import psutil
            import os
            process = psutil.Process(os.getpid())
            memory_mb = process.memory_info().rss / 1024 / 1024
            print(f"  Current memory usage: {memory_mb:.1f} MB")
            
    except Exception as e:
        print(f"Error in performance example: {e}")

def main():
    """Run all examples."""
    print("Python Bindings for Zig Poker AI - Examples")
    print("=" * 50)
    
    # Run all examples
    example_library_info()
    example_hand_evaluation()
    example_game_state()
    example_training_sync()
    
    # Run async example
    if BINDINGS_AVAILABLE:
        asyncio.run(example_training_async())
    
    example_compatibility_trainer()
    example_game_state_conversion()
    example_performance_comparison()
    
    print("\n" + "=" * 50)
    print("All examples completed!")
    
    if not BINDINGS_AVAILABLE:
        print("\nNote: Some examples were skipped due to missing bindings.")
        print("To run all examples, ensure the Zig library is built:")
        print("  cd zig && zig build")

if __name__ == "__main__":
    main()