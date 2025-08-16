#!/usr/bin/env python3
"""
Quick training script for a small poker AI agent for testing.
This trains a minimal agent with reduced iterations for fast testing.
"""

import os
import sys
from pathlib import Path
import logging
import time

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from poker_ai.ai.singleprocess.train import train
from poker_ai.games.texas_holdem.state import TexasHoldemPokerState

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def train_small_agent():
    """Train a small agent with minimal iterations for testing."""
    
    # Configuration for small/fast training
    config = {
        # Use fewer players for faster training
        "n_players": 2,  # Heads-up is fastest
        
        # Reduce iterations significantly for testing
        "n_iterations": 100,  # Very small for quick testing (normally 10000+)
        
        # Save checkpoints frequently
        "dump_iteration": 25,  # Save every 25 iterations
        "update_threshold": 0.0,  # Always update (no threshold)
        
        # Use single process for simplicity
        "use_multiprocess": False,
        
        # Paths
        "save_path": Path("./trained_agents/small_test_agent"),
        "lut_path": ".",  # Current directory for LUT files
        
        # Game settings
        "small_blind": 50,
        "big_blind": 100,
        
        # Strategy settings
        "strategy_interval": 10,  # Update strategy every 10 iterations
        "prune_threshold": 100,  # Prune infrequent paths
        "c": 1.0,  # Exploration constant for MCCFR
        "lcfr_threshold": 10,  # Linear CFR threshold
        "discount_interval": 10,  # Discount interval
        "n_players": 2,
    }
    
    # Create save directory
    config["save_path"].mkdir(parents=True, exist_ok=True)
    
    logger.info("=" * 60)
    logger.info("TRAINING SMALL POKER AI AGENT FOR TESTING")
    logger.info("=" * 60)
    logger.info(f"Configuration:")
    logger.info(f"  - Players: {config['n_players']}")
    logger.info(f"  - Iterations: {config['n_iterations']}")
    logger.info(f"  - Save path: {config['save_path']}")
    logger.info(f"  - Checkpoint every: {config['dump_iteration']} iterations")
    logger.info("=" * 60)
    
    start_time = time.time()
    
    try:
        # Train the agent
        logger.info("Starting training...")
        train(config)
        
        elapsed_time = time.time() - start_time
        logger.info("=" * 60)
        logger.info(f"✅ Training completed successfully!")
        logger.info(f"Time taken: {elapsed_time:.2f} seconds")
        logger.info(f"Agent saved to: {config['save_path']}")
        logger.info("=" * 60)
        
        # List saved files
        saved_files = list(config["save_path"].glob("*"))
        if saved_files:
            logger.info("\nSaved files:")
            for file in saved_files:
                size_mb = file.stat().st_size / (1024 * 1024)
                logger.info(f"  - {file.name} ({size_mb:.2f} MB)")
        
        return True
        
    except Exception as e:
        logger.error(f"Training failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def train_medium_agent():
    """Train a medium-sized agent with more iterations."""
    
    config = {
        "n_players": 4,  # More players
        "n_iterations": 1000,  # More iterations
        "dump_iteration": 100,
        "update_threshold": 0.0,
        "use_multiprocess": False,
        "save_path": Path("./trained_agents/medium_test_agent"),
        "lut_path": ".",
        "small_blind": 50,
        "big_blind": 100,
        "strategy_interval": 50,
        "prune_threshold": 200,
        "c": 1.0,
        "lcfr_threshold": 50,
        "discount_interval": 50,
    }
    
    config["save_path"].mkdir(parents=True, exist_ok=True)
    
    logger.info("Training medium agent with 4 players and 1000 iterations...")
    start_time = time.time()
    
    try:
        train(config)
        elapsed_time = time.time() - start_time
        logger.info(f"✅ Medium agent trained in {elapsed_time:.2f} seconds")
        return True
    except Exception as e:
        logger.error(f"Medium agent training failed: {e}")
        return False


def quick_test_agent():
    """Super quick agent for immediate testing (not good for actual play)."""
    
    config = {
        "n_players": 2,
        "n_iterations": 10,  # Extremely minimal
        "dump_iteration": 5,
        "update_threshold": 0.0,
        "use_multiprocess": False,
        "save_path": Path("./trained_agents/quick_test"),
        "lut_path": ".",
        "small_blind": 50,
        "big_blind": 100,
        "strategy_interval": 5,
        "prune_threshold": 10,
        "c": 1.0,
        "lcfr_threshold": 5,
        "discount_interval": 5,
    }
    
    config["save_path"].mkdir(parents=True, exist_ok=True)
    
    logger.info("Training quick test agent (10 iterations only)...")
    start_time = time.time()
    
    try:
        train(config)
        elapsed_time = time.time() - start_time
        logger.info(f"✅ Quick test agent trained in {elapsed_time:.2f} seconds")
        return True
    except Exception as e:
        logger.error(f"Quick test training failed: {e}")
        return False


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Train a small poker AI agent for testing")
    parser.add_argument(
        "--size",
        choices=["quick", "small", "medium"],
        default="small",
        help="Size of agent to train (quick=10 iter, small=100 iter, medium=1000 iter)"
    )
    parser.add_argument(
        "--players",
        type=int,
        default=None,
        help="Number of players (default: 2 for quick/small, 4 for medium)"
    )
    
    args = parser.parse_args()
    
    # Select training function based on size
    if args.size == "quick":
        success = quick_test_agent()
    elif args.size == "small":
        success = train_small_agent()
    else:  # medium
        success = train_medium_agent()
    
    if success:
        print("\n🎯 You can now test the trained agent using:")
        print("   uv run poker_ai play --strategy trained_agents/*/agent.joblib")
        sys.exit(0)
    else:
        sys.exit(1)