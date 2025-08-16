from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
from poker_ai.games.texas_holdem.state import TexasHoldemPokerState
from poker_ai.poker.pot import Pot


def default_state_to_visualise() -> TexasHoldemPokerState:
    """"""
    pot = Pot()
    n_players = 3
    players = [
        TexasHoldemPokerPlayer(player_i=player_i, initial_chips=10000, pot=pot)
        for player_i in range(n_players)
    ]
    return TexasHoldemPokerState(
        players=players, pickle_dir="../../research/blueprint_algo/"
    )


