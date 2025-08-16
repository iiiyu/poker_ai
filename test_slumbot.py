#!/usr/bin/env python3
"""
Test script for playing poker AI against Slumbot.
Usage: python test_slumbot.py --strategy_path path/to/strategy.gz --hands 100
"""

import argparse
import logging
import sys
from pathlib import Path
from datetime import datetime

from slumbot_integration import SlumbotPokerAI

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f'slumbot_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')
    ]
)
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser(description='Test poker AI against Slumbot')
    parser.add_argument(
        '--strategy_path',
        type=str,
        help='Path to trained strategy file (.gz)',
        default=None
    )
    parser.add_argument(
        '--hands',
        type=int,
        default=100,
        help='Number of hands to play (default: 100)'
    )
    parser.add_argument(
        '--username',
        type=str,
        default='hello_007_poker_ai',
        help='Slumbot username (default: hello_007_poker_ai)'
    )
    parser.add_argument(
        '--password',
        type=str,
        default='hello_007_poker_ai',
        help='Slumbot password (default: hello_007_poker_ai)'
    )
    parser.add_argument(
        '--no-auth',
        action='store_true',
        help='Play without authentication (no leaderboard)'
    )
    
    args = parser.parse_args()
    
    # Find strategy file if not provided
    if args.strategy_path is None:
        # Look for most recent strategy file
        strategy_files = list(Path('.').glob('**/offline_strategy*.gz'))
        if not strategy_files:
            logger.error("No strategy file found. Please train an agent first or specify --strategy_path")
            sys.exit(1)
        
        # Sort by modification time and get the most recent
        strategy_files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
        args.strategy_path = str(strategy_files[0])
        logger.info(f"Using most recent strategy file: {args.strategy_path}")
    
    # Verify strategy file exists
    if not Path(args.strategy_path).exists():
        logger.error(f"Strategy file not found: {args.strategy_path}")
        sys.exit(1)
    
    # Set up authentication
    username = None if args.no_auth else args.username
    password = None if args.no_auth else args.password
    
    if username and password:
        logger.info(f"Authenticating as user: {username}")
    else:
        logger.info("Playing without authentication (anonymous)")
    
    try:
        # Initialize the AI integration
        logger.info("Initializing poker AI integration...")
        ai = SlumbotPokerAI(
            agent_path=args.strategy_path,
            username=username,
            password=password
        )
        
        # Play the session
        logger.info(f"Starting session of {args.hands} hands against Slumbot...")
        stats = ai.play_session(num_hands=args.hands)
        
        # Print results
        print("\n" + "="*50)
        print("SESSION RESULTS")
        print("="*50)
        print(f"Total hands played: {stats['total_hands']}")
        print(f"Hands won: {stats['hands_won']}")
        print(f"Win rate: {stats['win_rate']:.1%}")
        print(f"Total winnings: {stats['total_winnings']:+d} chips")
        print(f"BB/100 hands: {stats['bb_per_100']:+.2f}")
        print("="*50)
        
        # Interpret results
        if stats['bb_per_100'] > 0:
            print("\n✅ Your bot is profitable against Slumbot!")
        elif stats['bb_per_100'] > -10:
            print("\n⚠️ Your bot is slightly losing but competitive.")
        else:
            print("\n❌ Your bot needs improvement to compete with Slumbot.")
        
    except Exception as e:
        logger.error(f"Error during testing: {e}", exc_info=True)
        sys.exit(1)

if __name__ == '__main__':
    main()