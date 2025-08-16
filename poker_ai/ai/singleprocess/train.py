"""
"""
from __future__ import annotations

import logging
import random
import time
from pathlib import Path
from typing import Dict, Union

import click
import joblib
import yaml
from tqdm import tqdm, trange

from poker_ai.ai.agent import Agent
from poker_ai.ai import ai
from poker_ai import utils
from poker_ai.games.texas_holdem.state import new_game, TexasHoldemPokerState


def print_strategy(strategy: Dict[str, Dict[str, int]]):
    """
    Print strategy.

    ...

    Parameters
    ----------
    strategy : Dict[str, Dict[str, int]]
        The preflop strategy for our agent.
    """
    for info_set, action_to_probabilities in sorted(strategy.items()):
        norm = sum(list(action_to_probabilities.values()))
        tqdm.write(f"{info_set}")
        for action, probability in action_to_probabilities.items():
            tqdm.write(f"  - {action}: {probability / norm:.2f}")


def simple_search(
    config: Dict[str, int],
    save_path: Path,
    lut_path: Union[str, Path],
    pickle_dir: bool,
    strategy_interval: int,
    n_iterations: int,
    lcfr_threshold: int,
    discount_interval: int,
    prune_threshold: int,
    c: int,
    n_players: int,
    dump_iteration: int,
    update_threshold: int,
):
    """
    Train agent.

    ...

    Parameters
    ----------
    config : Dict[str, int],
        Configurations for the simple search.
    save_path : str
        Path to save to.
    strategy_interval : int
        Iteration at which to update strategy.
    n_iterations : int
        Number of iterations.
    lcfr_threshold : int
        Iteration at which to begin linear CFR.
    discount_interval : int
        Iteration at which to discount strategy and regret.
    prune_threshold : int
        Iteration at which to begin pruning.
    c : int
        Floor for regret at which we do not search a node.
    n_players : int
        Number of players.
    dump_iteration : int
        Iteration at which we begin serialization.
    update_threshold : int
        Iteration at which we begin updating strategy.
    """
    utils.random.seed(42)
    agent = Agent(use_manager=False)
    card_info_lut = {}
    
    # Track performance metrics
    start_time = time.time()
    last_save_time = start_time
    iterations_since_save = 0
    
    pbar = trange(1, n_iterations + 1, desc="Training")
    for t in pbar:
        if t == 2:
            logging.disable(logging.DEBUG)
        
        iteration_start = time.time()
        iterations_since_save += 1
        
        for i in range(n_players):  # fixed position i
            # Create a new state.
            state: TexasHoldemPokerState = new_game(
                n_players,
                card_info_lut,
                lut_path=lut_path,
                pickle_dir=pickle_dir
            )
            card_info_lut = state.card_info_lut
            if t > update_threshold and t % strategy_interval == 0:
                ai.update_strategy(agent=agent, state=state, i=i, t=t)
            if t > prune_threshold:
                if random.uniform(0, 1) < 0.05:
                    ai.cfr(agent=agent, state=state, i=i, t=t)
                else:
                    ai.cfrp(agent=agent, state=state, i=i, t=t, c=c)
            else:
                ai.cfr(agent=agent, state=state, i=i, t=t)
        if t < lcfr_threshold and t % discount_interval == 0:
            d = (t / discount_interval) / ((t / discount_interval) + 1)
            for I in agent.regret.keys():
                for a in agent.regret[I].keys():
                    agent.regret[I][a] *= d
                    agent.strategy[I][a] *= d
        if t % dump_iteration == 0:
            # dump the current strategy (sigma) throughout training and then
            # take an average. This allows for estimation of expected value in
            # leaf nodes later on using modified versions of the blueprint
            # strategy.
            
            # Calculate performance metrics
            current_time = time.time()
            time_since_save = current_time - last_save_time
            if time_since_save > 0:
                iter_per_sec = iterations_since_save / time_since_save
            else:
                iter_per_sec = 0
            
            # Update progress description with performance info
            elapsed = current_time - start_time
            avg_speed = t / elapsed if elapsed > 0 else 0
            remaining = n_iterations - t
            eta = remaining / avg_speed if avg_speed > 0 else 0
            
            pbar.set_description(
                f"Iter {t}/{n_iterations} | Speed: {iter_per_sec:.1f} it/s | "
                f"Avg: {avg_speed:.1f} it/s | ETA: {eta/60:.1f}m | Saving..."
            )
            
            ai.serialise(
                agent=agent, save_path=save_path, t=t, server_state=config,
            )
            
            # Reset counters
            last_save_time = current_time
            iterations_since_save = 0
            
            pbar.set_description(
                f"Iter {t}/{n_iterations} | Speed: {iter_per_sec:.1f} it/s | "
                f"Avg: {avg_speed:.1f} it/s | ETA: {eta/60:.1f}m"
            )

    pbar.set_description("Training complete")
    pbar.close()  # Properly close the progress bar
    print("\nTraining completed successfully!")
    print_strategy(agent.strategy)


if __name__ == "__main__":
    train()
