#!/usr/bin/env python3
"""
Test script to measure actual training speed and provide recommendations.
"""

import time
import os
import sys
from pathlib import Path

# Add poker_ai to path
sys.path.insert(0, str(Path(__file__).parent))

def test_training_speed():
    """Test actual training speed with minimal iterations."""
    print("="*60)
    print("POKER AI TRAINING SPEED TEST")
    print("="*60)
    print("\nThis test will run 10 iterations to measure actual speed.")
    print("Please wait...\n")
    
    # Check if LUT exists
    if not Path('card_info_lut.joblib').exists():
        print("❌ ERROR: card_info_lut.joblib not found!")
        print("Please run: poker_ai cluster")
        print("This is required before training can start.")
        return
    
    from poker_ai.ai.agent import Agent
    from poker_ai.ai import ai
    from poker_ai import utils
    from poker_ai.games.texas_holdem.state import new_game
    
    # Test with different player counts
    player_counts = [2, 3, 4]
    results = {}
    
    for n_players in player_counts:
        print(f"\nTesting with {n_players} players...")
        
        utils.random.seed(42)
        agent = Agent(use_manager=False)
        card_info_lut = {}
        
        start_time = time.time()
        iterations = 10
        
        for t in range(1, iterations + 1):
            for i in range(n_players):
                state = new_game(
                    n_players,
                    card_info_lut,
                    lut_path=".",
                    pickle_dir=False
                )
                card_info_lut = state.card_info_lut
                
                # Run CFR (simplified version)
                ai.cfr(agent=agent, state=state, i=i, t=t)
        
        elapsed = time.time() - start_time
        iter_per_sec = iterations / elapsed
        
        results[n_players] = {
            'time': elapsed,
            'speed': iter_per_sec
        }
        
        print(f"  Time: {elapsed:.2f} seconds")
        print(f"  Speed: {iter_per_sec:.2f} iterations/second")
    
    # Print recommendations
    print("\n" + "="*60)
    print("RESULTS AND RECOMMENDATIONS")
    print("="*60)
    
    print("\n📊 Performance Summary:")
    for n_players, data in results.items():
        print(f"  {n_players} players: {data['speed']:.2f} it/s")
    
    # Calculate time estimates for different modes
    avg_speed = results[3]['speed']  # Use 3-player speed as default
    
    print(f"\n⏱️  Time Estimates (3 players, single process):")
    modes = [
        ("Test (100 iter)", 100),
        ("Quick (1K iter)", 1000),
        ("Medium (100K iter)", 100000),
        ("Long (1M iter)", 1000000)
    ]
    
    for mode_name, iterations in modes:
        seconds = iterations / avg_speed
        if seconds < 60:
            time_str = f"{seconds:.0f} seconds"
        elif seconds < 3600:
            time_str = f"{seconds/60:.1f} minutes"
        elif seconds < 86400:
            time_str = f"{seconds/3600:.1f} hours"
        else:
            time_str = f"{seconds/86400:.1f} days"
        print(f"  {mode_name:20s}: ~{time_str}")
    
    print("\n💡 Recommendations:")
    print("1. For quick testing, use 'test' mode (100 iterations)")
    print("2. Use --multi flag for ~2-3x speed improvement")
    print("3. Reduce players to 2 for faster training")
    print("4. Monitor progress with: python monitor_training.py")
    
    print("\n📝 Example commands:")
    print("  ./train_ai.sh test           # 100 iterations, ~30s-1m")
    print("  ./train_ai.sh quick --multi  # 1K iterations with multiprocess")
    print("  ./train_ai.sh medium --multi --players 2  # Faster medium training")

if __name__ == "__main__":
    test_training_speed()