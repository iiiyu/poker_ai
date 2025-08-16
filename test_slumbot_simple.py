#!/usr/bin/env python3
"""
Simple test script to verify Slumbot API connection.
Uses the basic check/call strategy from Slumbot's sample code.
"""

import argparse
import logging
import sys
from slumbot_client import SlumbotClient

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def play_hand_simple(client: SlumbotClient) -> int:
    """Play a single hand with simple check/call strategy.
    
    Args:
        client: SlumbotClient instance
        
    Returns:
        Winnings for the hand
    """
    # Start new hand
    r = client.new_hand()
    
    while True:
        logger.info('-' * 40)
        logger.info(f"State: {r}")
        
        action = r.get('action', '')
        client_pos = r.get('client_pos')
        hole_cards = r.get('hole_cards', [])
        board = r.get('board', [])
        winnings = r.get('winnings')
        
        logger.info(f"Action: {action}")
        if client_pos is not None:
            logger.info(f"Position: {'BB' if client_pos == 0 else 'SB'}")
        logger.info(f"Hole cards: {hole_cards}")
        logger.info(f"Board: {board}")
        
        # Check if hand is over
        if winnings is not None:
            logger.info(f"Hand complete. Winnings: {winnings}")
            return winnings
        
        # Parse action to determine what to do
        parsed = SlumbotClient.parse_action(action)
        if 'error' in parsed:
            logger.error(f"Error parsing action: {parsed['error']}")
            break
        
        # Simple strategy: always check or call
        if parsed['last_bettor'] != -1 and parsed['last_bet_size'] > 0:
            # There's a bet, so call
            incr = 'c'
        else:
            # No bet, so check
            incr = 'k'
        
        logger.info(f"Our action: {incr}")
        r = client.act(incr)
    
    return 0

def main():
    parser = argparse.ArgumentParser(description='Simple Slumbot API test')
    parser.add_argument(
        '--hands',
        type=int,
        default=10,
        help='Number of hands to play (default: 10)'
    )
    parser.add_argument(
        '--username',
        type=str,
        default='hello_007_poker_ai',
        help='Slumbot username'
    )
    parser.add_argument(
        '--password',
        type=str,
        default='hello_007_poker_ai',
        help='Slumbot password'
    )
    parser.add_argument(
        '--no-auth',
        action='store_true',
        help='Play without authentication'
    )
    
    args = parser.parse_args()
    
    # Initialize client
    username = None if args.no_auth else args.username
    password = None if args.no_auth else args.password
    
    try:
        logger.info("Connecting to Slumbot...")
        client = SlumbotClient(username=username, password=password)
        
        if username:
            logger.info(f"Authenticated as: {username}")
        else:
            logger.info("Playing anonymously")
        
        # Play hands
        total_winnings = 0
        for hand_num in range(args.hands):
            logger.info(f"\n{'='*50}")
            logger.info(f"HAND {hand_num + 1}/{args.hands}")
            logger.info('='*50)
            
            winnings = play_hand_simple(client)
            total_winnings += winnings
            
            logger.info(f"Running total: {total_winnings:+d} chips")
        
        # Final results
        bb_per_100 = (total_winnings / SlumbotClient.BIG_BLIND) / args.hands * 100
        
        print("\n" + "="*50)
        print("FINAL RESULTS")
        print("="*50)
        print(f"Hands played: {args.hands}")
        print(f"Total winnings: {total_winnings:+d} chips")
        print(f"BB/100: {bb_per_100:+.2f}")
        print("="*50)
        
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
        sys.exit(1)

if __name__ == '__main__':
    main()