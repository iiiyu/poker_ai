"""Tests for Texas Hold'em with full 52-card deck and up to 8 players."""
import pytest
import random
from typing import Tuple

from poker_ai.games.texas_holdem.state import TexasHoldemPokerState, new_game
from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
from poker_ai.games.factory import create_poker_game, get_deck_configuration
from poker_ai.poker.pot import Pot
from poker_ai.utils.random import seed


def _new_texas_holdem_game(
    n_players: int,
    small_blind: int = 50,
    big_blind: int = 100,
    initial_chips: int = 10000,
) -> Tuple[TexasHoldemPokerState, Pot]:
    """Create a new Texas Hold'em game."""
    pot = Pot()
    players = [
        TexasHoldemPokerPlayer(player_i=player_i, pot=pot, initial_chips=initial_chips)
        for player_i in range(n_players)
    ]
    state = TexasHoldemPokerState(
        players=players,
        load_card_lut=False,
        small_blind=small_blind,
        big_blind=big_blind,
    )
    return state, pot


@pytest.mark.parametrize("n_players", [2, 3, 4, 5, 6, 7, 8])
def test_texas_holdem_supports_up_to_8_players(n_players: int):
    """Test that Texas Hold'em supports 2-8 players."""
    state, _ = _new_texas_holdem_game(n_players=n_players)
    assert len(state.players) == n_players
    assert state._table.n_players == n_players
    
    # Verify all players have 2 cards
    for player in state.players:
        assert len(player.cards) == 2


@pytest.mark.parametrize(
    "n_players",
    [
        pytest.param(0, marks=pytest.mark.xfail),
        pytest.param(1, marks=pytest.mark.xfail),
        pytest.param(9, marks=pytest.mark.xfail),
        pytest.param(10, marks=pytest.mark.xfail),
    ],
)
def test_texas_holdem_invalid_player_count(n_players: int):
    """Test that Texas Hold'em rejects invalid player counts."""
    _new_texas_holdem_game(n_players=n_players)


def test_texas_holdem_full_deck():
    """Test that Texas Hold'em uses the full 52-card deck."""
    state, _ = _new_texas_holdem_game(n_players=4)
    
    # Check that deck has all ranks from 2-14 (2 through Ace)
    deck = state._table.dealer.deck
    deck.reset()
    
    # Count unique ranks in the deck
    ranks_found = set()
    suits_found = set()
    
    # Deal all cards from the deck
    cards_dealt = 0
    while True:
        try:
            card = deck.pick(random=False)
            ranks_found.add(card.rank_int)
            suits_found.add(card.suit)
            cards_dealt += 1
        except ValueError:
            # Deck is empty
            break
    
    # Should have 52 cards total
    assert cards_dealt == 52, f"Expected 52 cards, got {cards_dealt}"
    
    # Should have ranks 2-14
    expected_ranks = set(range(2, 15))
    assert ranks_found == expected_ranks, f"Missing ranks: {expected_ranks - ranks_found}"
    
    # Should have 4 suits
    assert len(suits_found) == 4


def test_texas_holdem_8_player_game():
    """Test a full 8-player Texas Hold'em game."""
    state, _ = _new_texas_holdem_game(n_players=8)
    
    # Play pre-flop round - all players call
    player_i_order = list(range(2, 8)) + [0, 1]  # Pre-flop order
    for i in range(8):
        assert state.player_i == player_i_order[i]
        assert state.betting_stage == "pre_flop"
        state = state.apply_action("call")
    
    # Should now be at flop
    assert state.betting_stage == "flop"
    assert len(state.community_cards) == 3
    
    # Play flop - all players call
    for i in range(8):
        assert state.player_i == i
        assert state.betting_stage == "flop"
        state = state.apply_action("call")
    
    # Should now be at turn
    assert state.betting_stage == "turn"
    assert len(state.community_cards) == 4
    
    # Play turn - all players call
    for i in range(8):
        assert state.player_i == i
        assert state.betting_stage == "turn"
        state = state.apply_action("call")
    
    # Should now be at river
    assert state.betting_stage == "river"
    assert len(state.community_cards) == 5
    
    # Play river - all players call
    for i in range(8):
        assert state.player_i == i
        assert state.betting_stage == "river"
        state = state.apply_action("call")
    
    # Should now be at showdown
    assert state.is_terminal
    assert state.betting_stage == "show_down"


def test_texas_holdem_factory():
    """Test creating Texas Hold'em game via factory function."""
    # Test valid configurations
    state = create_poker_game(game_type="texas_holdem", n_players=4)
    assert isinstance(state, TexasHoldemPokerState)
    assert len(state.players) == 4
    
    state = create_poker_game(game_type="texas_holdem", n_players=8)
    assert isinstance(state, TexasHoldemPokerState)
    assert len(state.players) == 8
    
    # Test invalid player count
    with pytest.raises(ValueError, match="2-8 players"):
        create_poker_game(game_type="texas_holdem", n_players=9)
    
    # Test deck configuration
    config = get_deck_configuration("texas_holdem")
    assert config["low_card_rank"] == 2
    assert config["high_card_rank"] == 14


def test_texas_holdem_vs_short_deck():
    """Compare Texas Hold'em with short deck to ensure they're different."""
    # Create both game types
    texas_holdem = create_poker_game(game_type="texas_holdem", n_players=4)
    short_deck = create_poker_game(game_type="short_deck", n_players=4)
    
    # Check deck sizes are different
    texas_holdem_deck = texas_holdem._table.dealer.deck
    short_deck_deck = short_deck._table.dealer.deck
    
    texas_holdem_deck.reset()
    short_deck_deck.reset()
    
    # Count cards in each deck
    texas_cards = 0
    short_cards = 0
    
    while True:
        try:
            texas_holdem_deck.pick(random=False)
            texas_cards += 1
        except ValueError:
            break
    
    while True:
        try:
            short_deck_deck.pick(random=False)
            short_cards += 1
        except ValueError:
            break
    
    assert texas_cards == 52, f"Texas Hold'em should have 52 cards, got {texas_cards}"
    assert short_cards == 20, f"Short deck should have 20 cards, got {short_cards}"


def test_texas_holdem_betting_with_8_players():
    """Test betting rounds work correctly with 8 players."""
    state, pot = _new_texas_holdem_game(n_players=8, small_blind=50, big_blind=100)
    
    # Check initial pot has blinds
    assert pot.total == 150  # Small blind + big blind
    
    # First player to act is player 2 (after big blind)
    assert state.player_i == 2
    
    # Have some players fold, some call, some raise
    state = state.apply_action("fold")  # Player 2 folds
    assert state.player_i == 3
    
    state = state.apply_action("call")  # Player 3 calls
    assert state.player_i == 4
    
    state = state.apply_action("raise")  # Player 4 raises
    assert state.player_i == 5
    
    # Continue with remaining players
    state = state.apply_action("call")  # Player 5 calls
    state = state.apply_action("fold")  # Player 6 folds
    state = state.apply_action("call")  # Player 7 calls
    state = state.apply_action("call")  # Player 0 (small blind) calls
    state = state.apply_action("call")  # Player 1 (big blind) calls
    
    # Now player 3 needs to call the raise
    assert state.player_i == 3
    state = state.apply_action("call")
    
    # Should move to flop
    assert state.betting_stage == "flop"
    
    # Count active players (8 - 2 folds = 6)
    active_count = sum(1 for p in state.players if p.is_active)
    assert active_count == 6