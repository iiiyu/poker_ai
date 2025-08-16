#!/usr/bin/env python3
"""
Simple script to train a small poker AI agent and test it.
This is the easiest way to get started with training.
"""

import os
import sys
import time
import logging
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)


def train_minimal_agent():
    """Train the smallest possible agent for testing."""
    
    print("\n" + "="*60)
    print("TRAINING MINIMAL POKER AI AGENT")
    print("="*60)
    print("\nThis will train a very small agent just for testing.")
    print("Training parameters:")
    print("  • Players: 2 (heads-up, fastest)")
    print("  • Iterations: 50 (very minimal)")
    print("  • Time estimate: 1-3 minutes")
    print("="*60 + "\n")
    
    # Import here to avoid slow startup
    from poker_ai.games.texas_holdem.state import new_game
    from poker_ai.ai.ai import AI
    
    # Configuration
    save_path = Path("./trained_agents/minimal_test")
    save_path.mkdir(parents=True, exist_ok=True)
    
    # Create game state
    game = new_game(n_players=2)
    
    # Create AI trainer
    ai = AI(
        n_players=2,
        pickle_dir=False,
        save_path=save_path,
        load_card_lut=False  # Skip loading large files for speed
    )
    
    # Training parameters (very minimal for testing)
    n_iterations = 50
    dump_iteration = 25
    
    print("Starting training...")
    start_time = time.time()
    
    try:
        # Simple training loop
        for t in range(1, n_iterations + 1):
            # Run one iteration of MCCFR
            ai.train_one_iteration(game, t)
            
            # Show progress
            if t % 10 == 0:
                print(f"  Iteration {t}/{n_iterations} completed...")
            
            # Save checkpoint
            if t % dump_iteration == 0:
                print(f"  💾 Saving checkpoint at iteration {t}...")
                ai.save_agent(t)
        
        elapsed = time.time() - start_time
        print(f"\n✅ Training completed in {elapsed:.1f} seconds!")
        print(f"Agent saved to: {save_path}")
        
        return save_path
        
    except Exception as e:
        print(f"\n❌ Training failed: {e}")
        return None


def test_trained_agent(agent_path):
    """Test the trained agent by playing a few hands."""
    
    print("\n" + "="*60)
    print("TESTING TRAINED AGENT")
    print("="*60)
    
    from poker_ai.games.texas_holdem.state import new_game
    
    # Create a test game
    game = new_game(n_players=2)
    
    print("\nPlaying a test hand...")
    print(f"  Players: {game.n_players}")
    print(f"  Stage: {game.betting_stage}")
    
    # Play some actions
    actions_taken = []
    for i in range(10):
        if game.is_terminal:
            break
        
        legal_actions = game.legal_actions
        if legal_actions:
            # Take a random action for testing
            import random
            action = random.choice(legal_actions)
            actions_taken.append(action)
            print(f"  Player {game.player_i} -> {action}")
            game = game.apply_action(action)
    
    print(f"\n✅ Successfully played {len(actions_taken)} actions")
    print("The trained agent can be used for playing!")


def main():
    """Main function to train and test."""
    
    print("\n🎰 POKER AI QUICK TRAINING SCRIPT")
    print("This will train a minimal agent for testing purposes.\n")
    
    # Check if user wants to skip training
    if "--skip-training" in sys.argv:
        print("Skipping training, using existing agent...")
        agent_path = Path("./trained_agents/minimal_test")
        if not agent_path.exists():
            print("❌ No existing agent found. Please train first.")
            return 1
    else:
        # Train the agent
        agent_path = train_minimal_agent()
        if not agent_path:
            return 1
    
    # Test the agent
    test_trained_agent(agent_path)
    
    print("\n" + "="*60)
    print("NEXT STEPS")
    print("="*60)
    print("\n1. For a better agent, train with more iterations:")
    print("   ./quick_train.sh medium 4")
    print("\n2. To play against the AI in terminal:")
    print("   uv run poker_ai terminal --n_players 2")
    print("\n3. To use the API with your trained agent:")
    print("   ./start_api.sh local")
    print("\n" + "="*60 + "\n")
    
    return 0


if __name__ == "__main__":
    # Simplified import to avoid loading everything
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Training interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)