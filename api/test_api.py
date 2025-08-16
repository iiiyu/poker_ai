#!/usr/bin/env python3
"""Test script for Poker AI API."""

import json
import asyncio
import requests
from datetime import datetime


def test_health_check():
    """Test health check endpoint."""
    print("Testing health check...")
    response = requests.get("http://localhost:8000/")
    assert response.status_code == 200
    data = response.json()
    print(f"✓ Health check passed: {data['status']}")
    return data


def test_create_game():
    """Test game creation."""
    print("\nTesting game creation...")
    payload = {
        "game_type": "texas_holdem",
        "n_players": 4,
        "ai_players": [1, 2, 3],
        "starting_chips": 10000,
        "small_blind": 50,
        "big_blind": 100
    }
    
    response = requests.post("http://localhost:8000/api/v1/games", json=payload)
    assert response.status_code == 200
    data = response.json()
    print(f"✓ Game created: {data['game_id']}")
    return data['game_id']


def test_get_game_state(game_id):
    """Test getting game state."""
    print(f"\nTesting get game state for {game_id}...")
    response = requests.get(f"http://localhost:8000/api/v1/games/{game_id}")
    assert response.status_code == 200
    data = response.json()
    print(f"✓ Game state retrieved: {data['status']}")
    print(f"  - Players: {len(data['players'])}")
    print(f"  - Current pot: {data['pot']}")
    print(f"  - Betting round: {data['betting_round']}")
    return data


def test_ai_action(game_id):
    """Test AI action recommendation."""
    print(f"\nTesting AI action for game {game_id}...")
    payload = {
        "player_cards": ["As", "Ks"],
        "community_cards": ["Ah", "Kd", "7c"],
        "pot": 500,
        "current_bet": 100,
        "player_chips": 9500,
        "opponents": [
            {"position": 1, "chips": 9900, "bet": 100}
        ],
        "betting_history": []
    }
    
    response = requests.post(
        f"http://localhost:8000/api/v1/games/{game_id}/ai-action",
        json=payload
    )
    assert response.status_code == 200
    data = response.json()
    print(f"✓ AI recommendation: {data['recommended_action']}")
    if data.get('amount'):
        print(f"  - Amount: {data['amount']}")
    print(f"  - Confidence: {data['confidence']:.2%}")
    print(f"  - Expected value: {data['expected_value']:.2f}")
    return data


def test_evaluate_hand():
    """Test hand evaluation."""
    print("\nTesting hand evaluation...")
    payload = {
        "game_type": "texas_holdem",
        "player_cards": ["Ac", "Ad"],
        "community_cards": ["Kh", "Qd", "Jc"],
        "pot": 1000,
        "to_call": 200,
        "player_chips": 5000,
        "n_opponents": 2
    }
    
    response = requests.post("http://localhost:8000/api/v1/ai/evaluate", json=payload)
    assert response.status_code == 200
    data = response.json()
    print(f"✓ Hand evaluated:")
    print(f"  - Hand strength: {data['hand_strength']:.2%}")
    print(f"  - Win probability: {data['win_probability']:.2%}")
    print(f"  - Recommendation: {data['recommended_action']}")
    print(f"  - Expected value: {data['expected_value']:.2f}")
    return data


def test_list_strategies():
    """Test listing strategies."""
    print("\nTesting list strategies...")
    response = requests.get("http://localhost:8000/api/v1/strategies")
    assert response.status_code == 200
    data = response.json()
    print(f"✓ Found {len(data)} strategies:")
    for strategy in data:
        print(f"  - {strategy['id']}: {strategy['description']}")
    return data


def run_all_tests():
    """Run all API tests."""
    print("=" * 50)
    print("POKER AI API TEST SUITE")
    print("=" * 50)
    
    try:
        # Test basic health
        health = test_health_check()
        
        # Test game creation and management
        game_id = test_create_game()
        game_state = test_get_game_state(game_id)
        
        # Test AI functionality
        ai_action = test_ai_action(game_id)
        evaluation = test_evaluate_hand()
        
        # Test strategy management
        strategies = test_list_strategies()
        
        print("\n" + "=" * 50)
        print("✓ ALL TESTS PASSED!")
        print("=" * 50)
        
    except requests.exceptions.ConnectionError:
        print("\n❌ ERROR: Cannot connect to API server")
        print("Make sure the server is running:")
        print("  - Docker: docker-compose up")
        print("  - Local: uvicorn api.main:app --reload")
        return False
    except AssertionError as e:
        print(f"\n❌ TEST FAILED: {e}")
        return False
    except Exception as e:
        print(f"\n❌ UNEXPECTED ERROR: {e}")
        return False
    
    return True


if __name__ == "__main__":
    success = run_all_tests()
    exit(0 if success else 1)