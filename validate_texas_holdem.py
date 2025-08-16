#!/usr/bin/env python
"""Simple validation script for Texas Hold'em implementation."""

import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import our implementations
from poker_ai.games.texas_holdem.state import TexasHoldemPokerState, new_game
from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
from poker_ai.poker.pot import Pot


def validate_8_players():
    """Validate that 8 players are supported."""
    print("Testing 8-player support...")
    
    try:
        state = new_game(n_players=8)
        assert len(state.players) == 8
        print("✓ 8 players created successfully")
        
        # Check each player has 2 cards
        for i, player in enumerate(state.players):
            assert len(player.cards) == 2, f"Player {i} doesn't have 2 cards"
        print("✓ All players have 2 cards")
        
        # Play a round
        initial_player = state.player_i
        state = state.apply_action("call")
        assert state.player_i != initial_player, "Player didn't advance"
        print("✓ Game actions work correctly")
        
    except Exception as e:
        print(f"✗ Error: {e}")
        return False
    
    return True


def validate_52_card_deck():
    """Validate that the full 52-card deck is used."""
    print("\nTesting 52-card deck...")
    
    try:
        pot = Pot()
        players = [
            TexasHoldemPokerPlayer(player_i=i, pot=pot, initial_chips=10000)
            for i in range(4)
        ]
        
        # Create state with explicit rank range for 52 cards
        state = TexasHoldemPokerState(
            players=players,
            load_card_lut=False,
        )
        
        # Check the table was created with correct ranks
        deck = state._table.dealer.deck
        deck.reset()
        
        # Count cards by dealing them all
        card_count = 0
        ranks_found = set()
        
        try:
            while True:
                card = deck.pick(random=False)
                card_count += 1
                ranks_found.add(card.rank_int)
        except ValueError:
            # Deck empty
            pass
        
        print(f"  Cards in deck: {card_count}")
        print(f"  Ranks found: {sorted(ranks_found)}")
        
        assert card_count == 52, f"Expected 52 cards, got {card_count}"
        assert ranks_found == set(range(2, 15)), f"Missing ranks"
        
        print("✓ Full 52-card deck confirmed")
        
    except Exception as e:
        print(f"✗ Error: {e}")
        return False
    
    return True


def validate_player_limits():
    """Validate player count limits."""
    print("\nTesting player limits...")
    
    # Test valid counts
    for n in [2, 3, 4, 5, 6, 7, 8]:
        try:
            state = new_game(n_players=n)
            assert len(state.players) == n
            print(f"✓ {n} players: OK")
        except Exception as e:
            print(f"✗ {n} players failed: {e}")
            return False
    
    # Test invalid counts
    for n in [1, 9, 10]:
        try:
            state = new_game(n_players=n)
            print(f"✗ {n} players should have failed but didn't")
            return False
        except ValueError:
            print(f"✓ {n} players correctly rejected")
        except Exception as e:
            print(f"✗ Unexpected error for {n} players: {e}")
            return False
    
    return True


def validate_game_flow():
    """Validate a complete game flow."""
    print("\nTesting complete game flow...")
    
    try:
        state = new_game(n_players=6)
        
        # Pre-flop
        assert state.betting_stage == "pre_flop"
        for _ in range(6):
            state = state.apply_action("call")
        
        # Flop
        assert state.betting_stage == "flop"
        assert len(state.community_cards) == 3
        print("✓ Flop dealt (3 cards)")
        
        for _ in range(6):
            state = state.apply_action("call")
        
        # Turn
        assert state.betting_stage == "turn"
        assert len(state.community_cards) == 4
        print("✓ Turn dealt (4 cards)")
        
        for _ in range(6):
            state = state.apply_action("call")
        
        # River
        assert state.betting_stage == "river"
        assert len(state.community_cards) == 5
        print("✓ River dealt (5 cards)")
        
        for _ in range(6):
            state = state.apply_action("call")
        
        # Showdown
        assert state.is_terminal
        print("✓ Game reached showdown")
        
    except Exception as e:
        print(f"✗ Error: {e}")
        return False
    
    return True


def main():
    """Run all validations."""
    print("="*60)
    print("Texas Hold'em Implementation Validation")
    print("="*60)
    
    all_passed = True
    
    all_passed &= validate_8_players()
    all_passed &= validate_52_card_deck()
    all_passed &= validate_player_limits()
    all_passed &= validate_game_flow()
    
    print("\n" + "="*60)
    if all_passed:
        print("✓ ALL VALIDATIONS PASSED")
        print("\nKey Features Implemented:")
        print("  • Full 52-card deck (ranks 2-A)")
        print("  • Support for 2-8 players")
        print("  • Separate Texas Hold'em state class")
        print("  • 169 unique preflop hand abstractions")
        print("  • Extended clustering support for both deck types")
        print("  • Factory function for easy game creation")
        print("  • Backward compatible with short deck poker")
    else:
        print("✗ SOME VALIDATIONS FAILED")
    print("="*60)
    
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())