"""Factory functions for creating poker games."""
from typing import Dict, Union

from poker_ai.games.short_deck.state import ShortDeckPokerState, new_game as new_short_deck_game
from poker_ai.games.texas_holdem.state import TexasHoldemPokerState, new_game as new_texas_holdem_game


def create_poker_game(
    game_type: str,
    n_players: int,
    small_blind: int = 50,
    big_blind: int = 100,
    card_info_lut: Dict = {},
    **kwargs
) -> Union[ShortDeckPokerState, TexasHoldemPokerState]:
    """
    Factory function to create a poker game of the specified type.
    
    Parameters
    ----------
    game_type : str
        Type of poker game - either "short_deck" or "texas_holdem"
    n_players : int
        Number of players (2-6 for short deck, 2-8 for Texas Hold'em)
    small_blind : int
        Small blind amount
    big_blind : int
        Big blind amount
    card_info_lut : Dict
        Card information lookup table for abstractions
    **kwargs
        Additional arguments passed to the game constructor
    
    Returns
    -------
    state : Union[ShortDeckPokerState, TexasHoldemPokerState]
        The initialized poker game state
    
    Raises
    ------
    ValueError
        If game_type is not recognized or n_players is out of range
    """
    if game_type == "short_deck":
        if n_players < 2 or n_players > 6:
            raise ValueError(
                f"Short deck poker supports 2-6 players, got {n_players}"
            )
        return new_short_deck_game(
            n_players=n_players,
            card_info_lut=card_info_lut,
            small_blind=small_blind,
            big_blind=big_blind,
            **kwargs
        )
    elif game_type == "texas_holdem":
        if n_players < 2 or n_players > 8:
            raise ValueError(
                f"Texas Hold'em supports 2-8 players, got {n_players}"
            )
        return new_texas_holdem_game(
            n_players=n_players,
            card_info_lut=card_info_lut,
            small_blind=small_blind,
            big_blind=big_blind,
            **kwargs
        )
    else:
        raise ValueError(
            f"Unknown game type: {game_type}. "
            f"Supported types are 'short_deck' and 'texas_holdem'"
        )


def get_deck_configuration(game_type: str) -> Dict[str, int]:
    """
    Get the deck configuration for a specific game type.
    
    Parameters
    ----------
    game_type : str
        Type of poker game - either "short_deck" or "texas_holdem"
    
    Returns
    -------
    config : Dict[str, int]
        Dictionary with 'low_card_rank' and 'high_card_rank'
    """
    if game_type == "short_deck":
        return {"low_card_rank": 10, "high_card_rank": 14}
    elif game_type == "texas_holdem":
        return {"low_card_rank": 2, "high_card_rank": 14}
    else:
        raise ValueError(f"Unknown game type: {game_type}")