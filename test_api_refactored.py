#!/usr/bin/env python3
"""Test the API with refactored Texas Hold'em code."""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

def test_api_imports():
    """Test that API imports work with refactored code."""
    print("Testing API imports...")
    
    try:
        from api.main import app, games_store, create_poker_game
        from api.models import GameType, CreateGameRequest
        print("  ✓ API imports successful")
        return True
    except Exception as e:
        print(f"  ✗ API import failed: {e}")
        return False


def test_api_game_creation():
    """Test API game creation with refactored code."""
    print("\nTesting API game creation...")
    
    try:
        from api.models import CreateGameRequest, GameType
        from poker_ai.games.factory import create_poker_game
        
        # Test Texas Hold'em creation
        request = CreateGameRequest(
            game_type=GameType.TEXAS_HOLDEM,
            n_players=4,
            ai_players=[1, 2, 3]
        )
        
        game = create_poker_game(
            request.game_type.value,
            n_players=request.n_players
        )
        
        assert game.n_players == 4
        print("  ✓ API creates Texas Hold'em game")
        
        # Test backward compatibility - SHORT_DECK should create Texas Hold'em
        request_compat = CreateGameRequest(
            game_type=GameType.SHORT_DECK,
            n_players=4,
            ai_players=[1, 2]
        )
        
        game_compat = create_poker_game(
            request_compat.game_type.value,
            n_players=request_compat.n_players
        )
        
        assert game_compat.n_players == 4
        print("  ✓ API backward compatibility works (SHORT_DECK -> Texas Hold'em)")
        
        return True
    except Exception as e:
        print(f"  ✗ API game creation failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_api_models():
    """Test that API models work correctly."""
    print("\nTesting API models...")
    
    try:
        from api.models import (
            GameType, ActionType, PlayerStatus, BettingRound,
            CreateGameRequest, AIActionRequest, EvaluateRequest
        )
        
        # Test enums
        assert GameType.TEXAS_HOLDEM.value == "texas_holdem"
        assert GameType.SHORT_DECK.value == "short_deck"
        print("  ✓ GameType enum works")
        
        # Test request models
        create_req = CreateGameRequest(
            game_type=GameType.TEXAS_HOLDEM,
            n_players=6,
            ai_players=[0, 1, 2, 3, 4]
        )
        assert create_req.n_players == 6
        print("  ✓ CreateGameRequest model works")
        
        # Test AI action request
        ai_req = AIActionRequest(
            player_cards=["As", "Ks"],
            community_cards=["Ah", "Kh", "7c"],
            pot=500,
            current_bet=100,
            player_chips=9500,
            opponents=[],
            betting_history=[]
        )
        assert len(ai_req.player_cards) == 2
        print("  ✓ AIActionRequest model works")
        
        return True
    except Exception as e:
        print(f"  ✗ API models test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_api_ai_logic():
    """Test that API AI decision logic works."""
    print("\nTesting API AI logic...")
    
    try:
        # Import the calculate_hand_strength function from main.py
        import sys
        sys.path.insert(0, 'api')
        from main import calculate_hand_strength
        
        # Test hand strength calculation
        strength = calculate_hand_strength(
            player_cards=["As", "Ks"],
            community_cards=["Ah", "Kh", "7c"]
        )
        
        assert 0 <= strength <= 1
        print(f"  ✓ Hand strength calculation works: {strength:.2f}")
        
        # Test with pocket pair
        pair_strength = calculate_hand_strength(
            player_cards=["Ac", "Ad"],
            community_cards=[]
        )
        
        assert pair_strength > 0.5  # Pocket aces should be strong
        print(f"  ✓ Pocket pair strength: {pair_strength:.2f}")
        
        return True
    except Exception as e:
        print(f"  ✗ API AI logic test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def run_all_tests():
    """Run all API tests."""
    print("=" * 60)
    print("API REFACTORING TEST SUITE")
    print("=" * 60)
    
    tests = [
        test_api_imports,
        test_api_models,
        test_api_game_creation,
        test_api_ai_logic,
    ]
    
    results = []
    for test in tests:
        results.append(test())
    
    print("\n" + "=" * 60)
    if all(results):
        print("✅ ALL API TESTS PASSED!")
    else:
        print(f"❌ {sum(not r for r in results)} API TESTS FAILED")
    print("=" * 60)
    
    return all(results)


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)