"""
Integration layer between poker AI agent and Slumbot API.
Translates between Slumbot's Texas Hold'em format and our agent's decision making.
"""

import logging
from typing import Dict, List, Optional, Tuple
import numpy as np
from pathlib import Path

from slumbot_client import SlumbotClient
from poker_ai.ai.agent import Agent
from poker_ai.games.short_deck.state import ShortDeckPokerState
from poker_ai.games.short_deck.player import ShortDeckPokerPlayer
from poker_ai.poker.card import Card
from poker_ai.poker.engine import PokerEngine
from poker_ai.poker.evaluation.eval_card import EvalCard

logger = logging.getLogger(__name__)

class SlumbotPokerAI:
    """Integration between poker AI agent and Slumbot API."""
    
    def __init__(self, agent_path: str, username: Optional[str] = None, password: Optional[str] = None):
        """Initialize the integration.
        
        Args:
            agent_path: Path to the trained agent strategy file
            username: Optional Slumbot username
            password: Optional Slumbot password
        """
        self.client = SlumbotClient(username, password)
        self.agent = Agent(agent_path, use_manager=False)
        self.current_hand = None
        self.our_position = None
        self.hole_cards = None
        self.board = []
        
    def convert_slumbot_action_to_amount(self, action_str: str, parsed: Dict, pot_size: int) -> int:
        """Convert Slumbot action to bet amount.
        
        Args:
            action_str: The action string (e.g., 'b200', 'c', 'k', 'f')
            parsed: Parsed action information
            pot_size: Current pot size
            
        Returns:
            Bet amount in chips (0 for check/fold, -1 for call)
        """
        if not action_str:
            return 0
            
        action_char = action_str[0]
        
        if action_char == 'k':  # Check
            return 0
        elif action_char == 'f':  # Fold
            return 0
        elif action_char == 'c':  # Call
            return -1  # Special value to indicate call
        elif action_char == 'b':  # Bet/Raise
            # Extract bet amount
            amount_str = action_str[1:]
            if amount_str.isdigit():
                return int(amount_str)
        return 0
    
    def get_action_from_agent(self, state: Dict) -> str:
        """Get action from the poker AI agent.
        
        Args:
            state: Current game state from Slumbot
            
        Returns:
            Action string to send to Slumbot ('c', 'k', 'f', or 'b<amount>')
        """
        # Parse the current action to understand game state
        action = state.get('action', '')
        parsed = SlumbotClient.parse_action(action)
        
        if 'error' in parsed:
            logger.error(f"Error parsing action: {parsed['error']}")
            # Default to check/call
            return 'c' if parsed.get('last_bet_size', 0) > 0 else 'k'
        
        # Determine current street (0=preflop, 1=flop, 2=turn, 3=river)
        street = parsed['st']
        
        # Get our position (0=BB, 1=SB)
        client_pos = state.get('client_pos', 0)
        
        # Check if it's our turn
        if parsed['pos'] != client_pos:
            # Not our turn yet, Slumbot is still acting
            return None
        
        # Calculate pot size
        pot_size = parsed['total_last_bet_to'] * 2
        
        # Convert cards to our format
        hole_cards = self.convert_cards_for_agent(state.get('hole_cards', []))
        board = self.convert_cards_for_agent(state.get('board', []))
        
        # Create a simplified state for decision making
        # Since our agent is trained on short deck, we need to adapt
        # For now, use a simple strategy based on hand strength
        
        # Calculate hand strength
        hand_strength = self.evaluate_hand_strength(hole_cards, board)
        
        # Simple decision logic (to be replaced with actual agent logic)
        last_bet_size = parsed.get('last_bet_size', 0)
        
        if last_bet_size == 0:
            # No bet to us, we can check or bet
            if hand_strength > 0.7:
                # Strong hand, bet
                bet_size = min(pot_size, SlumbotClient.STACK_SIZE - parsed['total_last_bet_to'])
                return f'b{bet_size}'
            else:
                # Check
                return 'k'
        else:
            # There's a bet to us
            pot_odds = last_bet_size / (pot_size + last_bet_size)
            
            if hand_strength > pot_odds + 0.1:
                # Good odds, call or raise
                if hand_strength > 0.8:
                    # Very strong, raise
                    raise_size = min(
                        parsed['street_last_bet_to'] + last_bet_size * 2,
                        SlumbotClient.STACK_SIZE - parsed['total_last_bet_to'] + last_bet_size
                    )
                    return f'b{raise_size}'
                else:
                    # Call
                    return 'c'
            else:
                # Fold
                return 'f'
    
    def convert_cards_for_agent(self, cards: List[str]) -> List[Card]:
        """Convert Slumbot card format to our Card format.
        
        Args:
            cards: List of cards in Slumbot format (e.g., ['Ac', '9d'])
            
        Returns:
            List of Card objects
        """
        result = []
        for card_str in cards:
            if len(card_str) == 2:
                rank = card_str[0]
                suit = card_str[1]
                
                # Convert rank
                rank_map = {
                    'A': 14, 'K': 13, 'Q': 12, 'J': 11, 'T': 10,
                    '9': 9, '8': 8, '7': 7, '6': 6, '5': 5,
                    '4': 4, '3': 3, '2': 2
                }
                rank_value = rank_map.get(rank, 0)
                
                # Convert suit
                suit_map = {'c': 0, 'd': 1, 'h': 2, 's': 3}
                suit_value = suit_map.get(suit, 0)
                
                # Create Card object (assuming Card takes rank and suit)
                card = Card(rank_value, suit_value)
                result.append(card)
        
        return result
    
    def evaluate_hand_strength(self, hole_cards: List[Card], board: List[Card]) -> float:
        """Evaluate hand strength (0-1 scale).
        
        Args:
            hole_cards: Player's hole cards
            board: Community cards
            
        Returns:
            Hand strength between 0 and 1
        """
        if not hole_cards:
            return 0.5
        
        # Simple hand strength evaluation
        # This is a placeholder - should use proper hand evaluation
        
        # Convert to eval format
        eval_cards = []
        for card in hole_cards + board:
            # Create eval card (simplified)
            eval_cards.append(card)
        
        # Basic heuristic based on high cards and pairs
        strength = 0.3  # Base strength
        
        # Check for pairs in hole cards
        if len(hole_cards) == 2 and hole_cards[0].rank == hole_cards[1].rank:
            strength += 0.3
        
        # High cards bonus
        for card in hole_cards:
            if card.rank >= 12:  # Q or better
                strength += 0.1
        
        # Adjust based on board
        if len(board) > 0:
            # Check for matches with board
            for hole_card in hole_cards:
                for board_card in board:
                    if hole_card.rank == board_card.rank:
                        strength += 0.2
        
        return min(1.0, strength)
    
    def play_hand(self) -> Tuple[Optional[int], Dict]:
        """Play a single hand against Slumbot.
        
        Returns:
            Tuple of (winnings, final_state)
        """
        # Start new hand
        state = self.client.new_hand()
        
        logger.info(f"New hand started. Position: {state.get('client_pos')}, "
                   f"Hole cards: {state.get('hole_cards')}")
        
        while True:
            # Check if hand is over
            if 'winnings' in state:
                winnings = state['winnings']
                logger.info(f"Hand complete. Winnings: {winnings}")
                return winnings, state
            
            # Get action from our agent
            our_action = self.get_action_from_agent(state)
            
            if our_action is not None:
                logger.info(f"Our action: {our_action}")
                # Send action to Slumbot
                state = self.client.act(our_action)
            else:
                # Slumbot is still acting, we need to wait for their action
                # This shouldn't happen in normal flow
                logger.warning("Unexpected state where it's not our turn")
                break
        
        return 0, state
    
    def play_session(self, num_hands: int = 100) -> Dict:
        """Play a session of hands against Slumbot.
        
        Args:
            num_hands: Number of hands to play
            
        Returns:
            Dictionary with session statistics
        """
        total_winnings = 0
        hands_won = 0
        hands_played = 0
        
        logger.info(f"Starting session of {num_hands} hands against Slumbot")
        
        for hand_num in range(num_hands):
            try:
                winnings, final_state = self.play_hand()
                if winnings is not None:
                    total_winnings += winnings
                    if winnings > 0:
                        hands_won += 1
                    hands_played += 1
                    
                    # Log progress every 10 hands
                    if (hand_num + 1) % 10 == 0:
                        bb_per_100 = (total_winnings / SlumbotClient.BIG_BLIND) / hands_played * 100
                        logger.info(f"Hands: {hands_played}, Winnings: {total_winnings}, "
                                   f"BB/100: {bb_per_100:.2f}")
                        
            except Exception as e:
                logger.error(f"Error in hand {hand_num + 1}: {e}")
                continue
        
        # Calculate statistics
        bb_per_100 = (total_winnings / SlumbotClient.BIG_BLIND) / hands_played * 100 if hands_played > 0 else 0
        
        stats = {
            'total_hands': hands_played,
            'hands_won': hands_won,
            'total_winnings': total_winnings,
            'bb_per_100': bb_per_100,
            'win_rate': hands_won / hands_played if hands_played > 0 else 0
        }
        
        logger.info(f"Session complete. Stats: {stats}")
        return stats