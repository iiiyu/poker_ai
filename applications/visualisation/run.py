import time

from plot import PokerPlot
from poker_ai.games.texas_holdem.player import TexasHoldemPokerPlayer
from poker_ai.games.texas_holdem.state import TexasHoldemPokerState
from poker_ai.poker.pot import Pot


def get_state() -> TexasHoldemPokerState:
    """Gets a state to visualise"""
    n_players = 6
    pot = Pot()
    players = [
        TexasHoldemPokerPlayer(player_i=player_i, initial_chips=10000, pot=pot)
        for player_i in range(n_players)
    ]
    return TexasHoldemPokerState(players=players, load_card_lut=False)


pp: PokerPlot = PokerPlot()
state: TexasHoldemPokerState = get_state()
time.sleep(5)
print("updating state")
pp.update_state(state)
