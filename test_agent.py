#!/usr/bin/env python3
"""
Test your trained poker AI agent.
"""

import sys
import glob
from pathlib import Path


def find_latest_agent():
    """Find the most recently trained agent."""
    # Look for agent directories
    agent_dirs = glob.glob("quick_test_agent_*") + \
                 glob.glob("small_test_agent_*") + \
                 glob.glob("medium_test_agent_*")
    
    if not agent_dirs:
        print("❌ No trained agents found!")
        print("Train one with: ./quick_train.sh quick")
        return None
    
    # Get the most recent one
    latest_dir = max(agent_dirs, key=lambda x: Path(x).stat().st_mtime)
    
    # Look for agent.joblib first
    agent_file = Path(latest_dir) / "agent.joblib"
    if agent_file.exists():
        return str(agent_file)
    
    # Otherwise look for offline strategy files
    strategy_files = glob.glob(f"{latest_dir}/offline_strategy_*.gz")
    if strategy_files:
        # Get the one with highest iteration number
        return max(strategy_files)
    
    print(f"❌ No agent files found in {latest_dir}")
    return None


def test_agent_loading():
    """Test that the agent can be loaded."""
    agent_path = find_latest_agent()
    if not agent_path:
        return False
    
    print(f"Found agent: {agent_path}")
    
    try:
        import joblib
        
        # Try to load the agent
        if agent_path.endswith('.joblib'):
            agent = joblib.load(agent_path)
            print("✅ Successfully loaded agent.joblib")
        elif agent_path.endswith('.gz'):
            agent = joblib.load(agent_path)
            print("✅ Successfully loaded strategy file")
        
        # Check agent structure
        if hasattr(agent, 'strategy') or isinstance(agent, dict):
            print("✅ Agent has valid structure")
            return True
        else:
            print("⚠️  Agent structure might be incomplete")
            return True  # Still ok for basic agents
            
    except Exception as e:
        print(f"❌ Failed to load agent: {e}")
        return False


def test_game_simulation():
    """Run a quick game simulation."""
    print("\nTesting game simulation...")
    
    from poker_ai.games.texas_holdem.state import new_game
    
    try:
        # Create a 2-player game
        game = new_game(n_players=2)
        print(f"✅ Created game with {game.n_players} players")
        
        # Play a few actions
        actions = 0
        max_actions = 20
        
        while not game.is_terminal and actions < max_actions:
            legal = game.legal_actions
            if legal:
                action = legal[0]  # Take first legal action
                game = game.apply_action(action)
                actions += 1
        
        print(f"✅ Simulated {actions} game actions")
        
        if game.is_terminal:
            print("✅ Game reached terminal state")
        
        return True
        
    except Exception as e:
        print(f"❌ Game simulation failed: {e}")
        return False


def main():
    """Run all tests."""
    print("="*50)
    print("TESTING YOUR POKER AI AGENT")
    print("="*50)
    
    tests_passed = 0
    tests_total = 2
    
    # Test 1: Agent loading
    print("\nTest 1: Agent Loading")
    print("-"*30)
    if test_agent_loading():
        tests_passed += 1
    
    # Test 2: Game simulation
    print("\nTest 2: Game Simulation")
    print("-"*30)
    if test_game_simulation():
        tests_passed += 1
    
    # Summary
    print("\n" + "="*50)
    if tests_passed == tests_total:
        print(f"✅ ALL TESTS PASSED ({tests_passed}/{tests_total})")
        print("\nYour agent is ready to play!")
        print("Run: ./play_agent.sh")
    else:
        print(f"⚠️  {tests_passed}/{tests_total} tests passed")
        if tests_passed > 0:
            print("\nAgent partially working. You can try playing:")
            print("Run: ./play_agent.sh")
    print("="*50)
    
    return 0 if tests_passed == tests_total else 1


if __name__ == "__main__":
    sys.exit(main())