"""
Slumbot API client for testing poker AI agents.
Implements the Slumbot API protocol for heads-up no-limit Texas Hold'em.
"""

import requests
import sys
from typing import Dict, List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)

class SlumbotClient:
    """Client for interacting with the Slumbot API."""
    
    HOST = 'slumbot.com'
    NUM_STREETS = 4
    SMALL_BLIND = 50
    BIG_BLIND = 100
    STACK_SIZE = 20000
    
    def __init__(self, username: Optional[str] = None, password: Optional[str] = None):
        """Initialize the Slumbot client.
        
        Args:
            username: Optional username for authentication
            password: Optional password for authentication
        """
        self.token = None
        if username and password:
            self.token = self.login(username, password)
    
    def login(self, username: str, password: str) -> str:
        """Login to Slumbot to get an authentication token.
        
        Args:
            username: Slumbot username
            password: Slumbot password
            
        Returns:
            Authentication token
        """
        data = {"username": username, "password": password}
        response = requests.post(
            f'https://{self.HOST}/slumbot/api/login',
            json=data,
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status_code != 200:
            logger.error(f'Login failed with status code: {response.status_code}')
            if response.text:
                logger.error(f'Error response: {response.text}')
            raise Exception(f'Login failed: {response.status_code}')
        
        r = response.json()
        if 'error_msg' in r:
            raise Exception(f'Login error: {r["error_msg"]}')
        
        token = r.get('token')
        if not token:
            raise Exception('No token received from login')
        
        logger.info('Successfully logged in to Slumbot')
        return token
    
    def new_hand(self) -> Dict:
        """Start a new hand.
        
        Returns:
            Dictionary containing hand information including:
            - token: Authentication token
            - client_pos: 0 for BB, 1 for SB
            - hole_cards: List of two card strings
            - board: List of community cards
            - action: Current action string
        """
        data = {}
        if self.token:
            data['token'] = self.token
        
        response = requests.post(
            f'https://{self.HOST}/slumbot/api/new_hand',
            json=data,
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status_code != 200:
            logger.error(f'New hand failed with status code: {response.status_code}')
            raise Exception(f'New hand failed: {response.status_code}')
        
        r = response.json()
        if 'error_msg' in r:
            raise Exception(f'New hand error: {r["error_msg"]}')
        
        # Update token if provided
        new_token = r.get('token')
        if new_token:
            self.token = new_token
        
        return r
    
    def act(self, action: str) -> Dict:
        """Take an action in the current hand.
        
        Args:
            action: Action string ('c' for call, 'k' for check, 'f' for fold, 'b<amount>' for bet)
            
        Returns:
            Dictionary containing updated hand state
        """
        if not self.token:
            raise Exception('No token available, need to start a new hand first')
        
        data = {'token': self.token, 'incr': action}
        response = requests.post(
            f'https://{self.HOST}/slumbot/api/act',
            json=data,
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status_code != 200:
            logger.error(f'Act failed with status code: {response.status_code}')
            raise Exception(f'Act failed: {response.status_code}')
        
        r = response.json()
        if 'error_msg' in r:
            raise Exception(f'Act error: {r["error_msg"]}')
        
        # Update token if provided
        new_token = r.get('token')
        if new_token:
            self.token = new_token
        
        return r
    
    @staticmethod
    def parse_action(action: str) -> Dict:
        """Parse a Slumbot action string.
        
        Args:
            action: Action string like 'b200c/kk/kk/kb200'
            
        Returns:
            Dictionary with parsed action information
        """
        if not action:
            return {
                'st': 0,
                'pos': 1,
                'street_last_bet_to': SlumbotClient.BIG_BLIND,
                'total_last_bet_to': SlumbotClient.BIG_BLIND,
                'last_bet_size': SlumbotClient.BIG_BLIND - SlumbotClient.SMALL_BLIND,
                'last_bettor': 0,
            }
        
        st = 0  # Current street
        street_last_bet_to = SlumbotClient.BIG_BLIND
        total_last_bet_to = SlumbotClient.BIG_BLIND
        last_bet_size = SlumbotClient.BIG_BLIND - SlumbotClient.SMALL_BLIND
        last_bettor = 0
        pos = 1  # Position of next player to act
        
        i = 0
        sz = len(action)
        check_or_call_ends_street = False
        
        while i < sz:
            if st >= SlumbotClient.NUM_STREETS:
                return {'error': 'Unexpected error'}
            
            c = action[i]
            i += 1
            
            if c == '/':
                # Street separator
                st += 1
                street_last_bet_to = 0
                last_bet_size = 0
                pos = 0
                check_or_call_ends_street = False
            elif c == 'k':  # Check
                if last_bet_size > 0:
                    return {'error': 'Illegal check'}
                if check_or_call_ends_street:
                    if st < SlumbotClient.NUM_STREETS - 1 and i < sz and action[i] == '/':
                        i += 1
                        st += 1
                        street_last_bet_to = 0
                        pos = 0
                    elif st == SlumbotClient.NUM_STREETS - 1:
                        pos = -1  # Showdown
                    check_or_call_ends_street = False
                else:
                    pos = (pos + 1) % 2
                    check_or_call_ends_street = True
            elif c == 'c':  # Call
                if last_bet_size == 0:
                    return {'error': 'Illegal call'}
                if check_or_call_ends_street:
                    if st < SlumbotClient.NUM_STREETS - 1 and i < sz and action[i] == '/':
                        i += 1
                        st += 1
                        street_last_bet_to = 0
                        pos = 0
                    elif st == SlumbotClient.NUM_STREETS - 1:
                        pos = -1  # Showdown
                    check_or_call_ends_street = False
                else:
                    pos = (pos + 1) % 2
                    check_or_call_ends_street = True
                last_bet_size = 0
            elif c == 'f':  # Fold
                if last_bet_size == 0:
                    return {'error': 'Illegal fold'}
                pos = -1  # Hand over
                break
            elif c == 'b':  # Bet/Raise
                j = i
                while i < sz and action[i].isdigit():
                    i += 1
                if i == j:
                    return {'error': 'Missing bet size'}
                
                new_street_last_bet_to = int(action[j:i])
                new_last_bet_size = new_street_last_bet_to - street_last_bet_to
                street_last_bet_to = new_street_last_bet_to
                total_last_bet_to += new_last_bet_size
                last_bet_size = new_last_bet_size
                last_bettor = pos
                pos = (pos + 1) % 2
                check_or_call_ends_street = True
        
        return {
            'st': st,
            'pos': pos,
            'street_last_bet_to': street_last_bet_to,
            'total_last_bet_to': total_last_bet_to,
            'last_bet_size': last_bet_size,
            'last_bettor': last_bettor,
        }
    
    @staticmethod
    def convert_cards_to_standard(cards: List[str]) -> List[str]:
        """Convert Slumbot card format to standard format.
        
        Args:
            cards: List of cards in Slumbot format (e.g., ['Ac', '9d'])
            
        Returns:
            List of cards in standard format (e.g., ['A♣', '9♦'])
        """
        suit_map = {'c': '♣', 'd': '♦', 'h': '♥', 's': '♠'}
        result = []
        for card in cards:
            if len(card) == 2:
                rank = card[0]
                suit = card[1]
                if rank == 'T':
                    rank = '10'
                result.append(f'{rank}{suit_map.get(suit, suit)}')
        return result
    
    @staticmethod
    def convert_card_to_slumbot(card: str) -> str:
        """Convert standard card format to Slumbot format.
        
        Args:
            card: Card in standard format (e.g., 'A♣' or 'Ac')
            
        Returns:
            Card in Slumbot format (e.g., 'Ac')
        """
        # Handle both unicode and letter suits
        suit_map = {'♣': 'c', '♦': 'd', '♥': 'h', '♠': 's',
                   'c': 'c', 'd': 'd', 'h': 'h', 's': 's'}
        
        if len(card) >= 2:
            rank = card[:-1]
            suit = card[-1]
            if rank == '10':
                rank = 'T'
            return f'{rank}{suit_map.get(suit, suit)}'
        return card