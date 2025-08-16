#!/usr/bin/env python3
"""Test script to verify the refactored Texas Hold'em implementation."""

import sys
import traceback
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

def test_game_creation():
    """Test basic game creation."""
    print("Testing game creation...")
    
    try:
        from poker_ai.games.texas_holdem.state import new_game
        
        # Test with different player counts
        for n_players in [2, 4, 6, 8]:
            game = new_game(n_players=n_players)
            assert len(game.players) == n_players
            assert game.n_players == n_players
            print(f"  ✓ Created game with {n_players} players")
        
        print("  ✓ Game creation test passed")
        return True
    except Exception as e:
        print(f"  ✗ Game creation test failed: {e}")
        traceback.print_exc()
        return False


def test_factory_pattern():
    """Test the factory pattern."""
    print("\nTesting factory pattern...")
    
    try:
        from poker_ai.games.factory import create_poker_game
        
        # Test Texas Hold'em creation
        game = create_poker_game("texas_holdem", n_players=4)
        assert game.n_players == 4
        print("  ✓ Factory creates Texas Hold'em correctly")
        
        # Test backward compatibility - short_deck should create Texas Hold'em
        game_compat = create_poker_game("short_deck", n_players=4)
        assert game_compat.n_players == 4
        assert type(game_compat).__name__ == "TexasHoldemPokerState"
        print("  ✓ Backward compatibility works (short_deck -> texas_holdem)")
        
        print("  ✓ Factory pattern test passed")
        return True
    except Exception as e:
        print(f"  ✗ Factory pattern test failed: {e}")
        traceback.print_exc()
        return False


def test_game_flow():
    """Test basic game flow."""
    print("\nTesting game flow...")
    
    try:
        from poker_ai.games.texas_holdem.state import new_game
        
        # Create a game
        game = new_game(n_players=4)
        initial_player = game.current_player
        
        # Test some actions
        actions_taken = []
        for i in range(8):  # Play some actions
            if game.is_terminal:
                break
            
            legal_actions = game.legal_actions
            if legal_actions:
                action = legal_actions[0]  # Take first legal action
                new_game = game.apply_action(action)
                actions_taken.append(action)
                game = new_game
                print(f"  ✓ Applied action: {action}")
        
        print(f"  ✓ Successfully played {len(actions_taken)} actions")
        print("  ✓ Game flow test passed")
        return True
    except Exception as e:
        print(f"  ✗ Game flow test failed: {e}")
        traceback.print_exc()
        return False


def test_player_implementation():
    """Test player implementation."""
    print("\nTesting player implementation...")
    
    try:
        from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
        from poker_ai.poker.pot import Pot
        
        # Create a pot and player
        pot = Pot()
        player = TexasHoldemPokerPlayer(player_i=0, initial_chips=10000, pot=pot, name="TestPlayer")
        
        assert player.player_i == 0
        assert player.n_chips == 10000
        assert player.name == "TestPlayer"
        assert player.is_active == True
        print("  ✓ Player created successfully")
        
        # Test add_to_pot method
        player.add_to_pot(100)
        assert player.n_chips == 9900
        print("  ✓ Add to pot method works")
        
        # Test fold method
        player.fold()
        assert player.is_active == False
        print("  ✓ Fold method works")
        
        print("  ✓ Player implementation test passed")
        return True
    except Exception as e:
        print(f"  ✗ Player implementation test failed: {e}")
        traceback.print_exc()
        return False


def test_imports():
    """Test that all necessary imports work."""
    print("\nTesting imports...")
    
    try:
        # Test main game imports
        from poker_ai.games.texas_holdem.state import TexasHoldemPokerState
        from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
        from poker_ai.games.factory import create_poker_game
        print("  ✓ Game imports work")
        
        # Test AI module imports (check what's actually exported)
        try:
            from poker_ai.ai import ai as ai_module
            from poker_ai.ai.agent import Agent
            print("  ✓ AI imports work")
        except ImportError as e:
            print(f"  ⚠ AI import warning: {e}")
        
        # Test that short deck imports are gone
        try:
            from poker_ai.games.short_deck.state import ShortDeckPokerState
            print("  ✗ Short deck imports still exist (should be removed)")
            return False
        except ImportError:
            print("  ✓ Short deck imports properly removed")
        
        print("  ✓ Import test passed")
        return True
    except Exception as e:
        print(f"  ✗ Import test failed: {e}")
        traceback.print_exc()
        return False


def run_all_tests():
    """Run all tests."""
    print("=" * 60)
    print("REFACTORING TEST SUITE")
    print("=" * 60)
    
    tests = [
        test_imports,
        test_game_creation,
        test_factory_pattern,
        test_player_implementation,
        test_game_flow,
    ]
    
    results = []
    for test in tests:
        results.append(test())
    
    print("\n" + "=" * 60)
    if all(results):
        print("✅ ALL TESTS PASSED!")
    else:
        print(f"❌ {sum(not r for r in results)} TESTS FAILED")
    print("=" * 60)
    
    return all(results)


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)