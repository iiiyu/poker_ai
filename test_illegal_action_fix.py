#!/usr/bin/env python3
"""
Test that the illegal action fix works correctly.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from poker_ai.ai.agent import Agent
from poker_ai.ai import ai
from poker_ai.games.texas_holdem.state import new_game
from poker_ai import utils

def test_cfrp_with_limited_actions():
    """Test that cfrp handles states with limited legal actions correctly."""
    print("Testing CFRP with limited legal actions...")
    
    utils.random.seed(42)
    agent = Agent(use_manager=False)
    n_players = 3
    
    # Run a few iterations to build up regret
    for t in range(1, 11):
        print(f"Iteration {t}...", end="")
        try:
            for i in range(n_players):
                state = new_game(n_players, {})
                
                # Use cfrp which had the bug
                ai.cfrp(agent=agent, state=state, i=i, t=t, c=-20000, locks={})
            print(" ✓")
        except ValueError as e:
            if "not in legal actions" in str(e):
                print(f" ✗ ERROR: {e}")
                print("The fix did not work properly!")
                return False
            else:
                raise
    
    print("\n✅ All iterations completed successfully!")
    print("The illegal action fix is working correctly.")
    return True

def test_cfr_with_limited_actions():
    """Test that regular cfr also handles states with limited legal actions correctly."""
    print("\nTesting CFR with limited legal actions...")
    
    utils.random.seed(42)
    agent = Agent(use_manager=False)
    n_players = 3
    
    # Run a few iterations
    for t in range(1, 6):
        print(f"Iteration {t}...", end="")
        try:
            for i in range(n_players):
                state = new_game(n_players, {})
                
                # Use regular cfr
                ai.cfr(agent=agent, state=state, i=i, t=t, locks={})
            print(" ✓")
        except ValueError as e:
            if "not in legal actions" in str(e):
                print(f" ✗ ERROR: {e}")
                print("CFR also has issues with illegal actions!")
                return False
            else:
                raise
    
    print("\n✅ CFR iterations completed successfully!")
    return True

if __name__ == "__main__":
    print("="*60)
    print("ILLEGAL ACTION FIX TEST")
    print("="*60)
    
    success = True
    
    # Test both functions
    success = test_cfrp_with_limited_actions() and success
    success = test_cfr_with_limited_actions() and success
    
    if success:
        print("\n" + "="*60)
        print("✅ ALL TESTS PASSED!")
        print("The illegal action fix is working correctly.")
        print("You can now run training on your server without this error.")
        print("="*60)
    else:
        print("\n" + "="*60)
        print("❌ TESTS FAILED!")
        print("There may still be issues with illegal actions.")
        print("="*60)
        sys.exit(1)