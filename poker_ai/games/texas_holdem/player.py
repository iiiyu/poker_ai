"""Texas Hold'em player implementation."""
from typing import Optional, List, TYPE_CHECKING
from poker_ai.poker.player import Player

if TYPE_CHECKING:
    from poker_ai.poker.card import Card
    from poker_ai.poker.pot import Pot


class TexasHoldemPokerPlayer(Player):
    """
    A player in a Texas Hold'em poker game.
    
    Extends the base Player class with Texas Hold'em specific functionality.
    """
    
    def __init__(self, player_i: int, initial_chips: int = 10000, pot: Optional['Pot'] = None, name: Optional[str] = None):
        """
        Initialize a Texas Hold'em player.
        
        Parameters
        ----------
        player_i : int
            The player's index/position
        initial_chips : int
            Starting chip count
        pot : Optional[Pot]
            Reference to the pot object
        name : Optional[str]
            Player name, defaults to Player_{player_i}
        """
        if name is None:
            name = f"Player_{player_i}"
        
        # Initialize parent class
        super().__init__(name=name, initial_chips=initial_chips, pot=pot)
        
        # Texas Hold'em specific attributes
        self.player_i = player_i
        self.has_folded = False
        self._is_all_in = False
        
    def __repr__(self):
        """String representation of the player."""
        return f"<TexasHoldemPokerPlayer player_i={self.player_i} chips={self.n_chips} active={self._is_active}>"
    
    def reset_for_new_round(self):
        """Reset player state for a new hand."""
        self.cards = []
        self._is_active = True
        self.has_folded = False
        self._is_all_in = False
    
    @property
    def is_active(self) -> bool:
        """Check if player is active."""
        return self._is_active
    
    @is_active.setter
    def is_active(self, value: bool):
        """Set player active status."""
        self._is_active = value
    
    @property
    def n_bet_chips(self) -> int:
        """Get the total chips bet by this player."""
        if self.pot:
            return self.pot[self]  # Use __getitem__ method
        return 0
    
    @property
    def is_all_in(self) -> bool:
        """Check if player is all in."""
        return self._is_all_in
    
    @is_all_in.setter
    def is_all_in(self, value: bool):
        """Set player all in status."""
        self._is_all_in = value