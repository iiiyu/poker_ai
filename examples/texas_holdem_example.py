#!/usr/bin/env python
"""Example script demonstrating Texas Hold'em with 52 cards and up to 8 players."""

import logging
from poker_ai.games.factory import create_poker_game, get_deck_configuration
from poker_ai.clustering.card_info_lut_builder_extended import CardInfoLutBuilderExtended

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def demo_texas_holdem_game():
    """Demonstrate a Texas Hold'em game with 8 players."""
    logger.info("Creating Texas Hold'em game with 8 players...")
    
    # Create a Texas Hold'em game with 8 players
    state = create_poker_game(
        game_type="texas_holdem",
        n_players=8,
        small_blind=50,
        big_blind=100
    )
    
    logger.info(f"Game created: {state}")
    logger.info(f"Number of players: {len(state.players)}")
    logger.info(f"Current player: {state.current_player.name}")
    logger.info(f"Betting stage: {state.betting_stage}")
    
    # Play a round where everyone calls
    logger.info("\nPlaying pre-flop round (all players call)...")
    for i in range(8):
        current_player = state.current_player.name
        action = "call"
        logger.info(f"  {current_player} -> {action}")
        state = state.apply_action(action)
    
    logger.info(f"\nMoved to {state.betting_stage}")
    logger.info(f"Community cards: {len(state.community_cards)} cards on table")
    
    # Play flop
    logger.info("\nPlaying flop round (mix of actions)...")
    actions = ["call", "raise", "call", "fold", "call", "call", "call"]
    active_players = [p for p in state.players if p.is_active]
    
    for i, player in enumerate(active_players):
        if i < len(actions):
            current_player = state.current_player.name
            action = actions[i]
            logger.info(f"  {current_player} -> {action}")
            state = state.apply_action(action)
    
    logger.info(f"\nActive players remaining: {sum(1 for p in state.players if p.is_active)}")
    
    return state


def demo_clustering_setup():
    """Demonstrate setting up clustering for Texas Hold'em."""
    logger.info("\nSetting up clustering for Texas Hold'em...")
    
    # Get deck configuration
    config = get_deck_configuration("texas_holdem")
    logger.info(f"Deck configuration: ranks {config['low_card_rank']}-{config['high_card_rank']}")
    
    # Create the lookup table builder
    builder = CardInfoLutBuilderExtended(
        n_simulations_river=100,  # Use small numbers for demo
        n_simulations_turn=100,
        n_simulations_flop=100,
        low_card_rank=config["low_card_rank"],
        high_card_rank=config["high_card_rank"],
        save_dir="./texas_holdem_luts",
        deck_type="texas_holdem"
    )
    
    logger.info(f"Created LUT builder for Texas Hold'em")
    logger.info(f"Number of possible starting hands: {len(builder.starting_hands)}")
    
    # Note: Actually computing clusters would take a very long time
    # especially for the full 52-card deck
    logger.info("\nNote: Full clustering computation would take significant time.")
    logger.info("For production use, pre-compute and save the lookup tables.")
    
    return builder


def compare_game_types():
    """Compare short deck vs Texas Hold'em."""
    logger.info("\n" + "="*60)
    logger.info("Texas Hold'em Configuration")
    logger.info("="*60)
    
    # Create Texas Hold'em game
    texas_holdem = create_poker_game(game_type="texas_holdem", n_players=4)
    
    # Get deck configuration
    texas_holdem_config = get_deck_configuration("texas_holdem")
    
    logger.info("\nTexas Hold'em:")
    logger.info(f"  - Ranks: {texas_holdem_config['low_card_rank']}-{texas_holdem_config['high_card_rank']} (2-A)")
    logger.info(f"  - Total cards: 52 (13 ranks × 4 suits)")
    logger.info(f"  - Max players: 8")
    logger.info(f"  - Starting hand combinations: ~1326")
    logger.info(f"  - Unique starting hands: 169")


def main():
    """Run all demonstrations."""
    logger.info("Texas Hold'em Implementation Demo")
    logger.info("=================================\n")
    
    # Demo game play
    state = demo_texas_holdem_game()
    
    # Demo clustering setup
    builder = demo_clustering_setup()
    
    # Compare game types
    compare_game_types()
    
    logger.info("\n" + "="*60)
    logger.info("Demo complete!")
    logger.info("="*60)


if __name__ == "__main__":
    main()