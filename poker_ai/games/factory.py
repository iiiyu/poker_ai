"""Factory function for creating Texas Hold'em poker games."""
from typing import Dict

from poker_ai.games.texas_holdem.state import TexasHoldemPokerState, new_game as new_texas_holdem_game


def create_poker_game(
    game_type: str = "texas_holdem",
    n_players: int = 6,
    small_blind: int = 50,
    big_blind: int = 100,
    card_info_lut: Dict = {},
    **kwargs
) -> TexasHoldemPokerState:
    """
    Create a Texas Hold'em poker game.
    
    Parameters
    ----------
    game_type : str
        Type of poker game - accepts "texas_holdem" or "short_deck" for backward compatibility.
        Both map to Texas Hold'em. Default is "texas_holdem".
    n_players : int
        Number of players (2-8)
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
    state : TexasHoldemPokerState
        The initialized Texas Hold'em game state
    
    Raises
    ------
    ValueError
        If n_players is out of range (2-8)
    """
    # Accept both for backward compatibility, but always create Texas Hold'em
    if game_type not in ["texas_holdem", "short_deck"]:
        raise ValueError(
            f"Unknown game type: {game_type}. "
            f"Use 'texas_holdem'"
        )
    
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


def get_deck_configuration(game_type: str = "texas_holdem") -> Dict[str, int]:
    """
    Get the deck configuration for Texas Hold'em.
    
    Parameters
    ----------
    game_type : str
        Ignored - always returns Texas Hold'em configuration
    
    Returns
    -------
    config : Dict[str, int]
        Dictionary with 'low_card_rank' (2) and 'high_card_rank' (14)
    """
    # Always return Texas Hold'em configuration
    return {"low_card_rank": 2, "high_card_rank": 14}