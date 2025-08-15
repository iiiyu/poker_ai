"""Preflop abstractions for full 52-card Texas Hold'em.

For Texas Hold'em with 52 cards, there are 169 unique starting hands:
- 13 pocket pairs (AA, KK, QQ, ..., 22)
- 78 suited non-pairs (AKs, AQs, ..., 32s)
- 78 unsuited non-pairs (AKo, AQo, ..., 32o)
"""
from typing import Dict, Tuple, List
import operator

from poker_ai.poker.card import Card


def make_texas_holdem_starting_hand_lossless(starting_hand) -> int:
    """Create lossless abstraction for Texas Hold'em starting hands.
    
    Returns an integer from 0-168 representing one of the 169 unique
    starting hand combinations in Texas Hold'em.
    """
    ranks = []
    suits = []
    for card in starting_hand:
        ranks.append(card.rank_int)
        suits.append(card.suit)
    
    # Sort ranks in descending order
    ranks.sort(reverse=True)
    suited = len(set(suits)) == 1
    
    # Map to 169 unique starting hands
    # Strategy: Use a formula based on high card, low card, and suited/unsuited
    high_rank = ranks[0]
    low_rank = ranks[1]
    
    # Pocket pairs: 0-12 (AA=0, KK=1, ..., 22=12)
    if high_rank == low_rank:
        return 14 - high_rank
    
    # Non-pairs: calculate position in triangular matrix
    # For each high card, there are (high_card - 2) possible lower cards
    # Suited hands come first, then unsuited
    base_index = 13  # Start after pocket pairs
    
    # Calculate position based on high card
    for h in range(14, high_rank, -1):
        base_index += 2 * (h - 2)  # Each high card has (h-2) suited and (h-2) unsuited combos
    
    # Add offset for this specific combination
    offset = (high_rank - low_rank - 1) * 2
    if suited:
        return base_index + offset
    else:
        return base_index + offset + 1


def compute_preflop_lossless_abstraction_texas_holdem(builder) -> Dict[Tuple[Card, Card], int]:
    """Compute the preflop abstraction dictionary for Texas Hold'em.
    
    Works for the full 52-card deck with all ranks 2-A.
    """
    # Making sure this is 52 card deck
    allowed_ranks = set(range(2, 15))  # 2 through Ace (14)
    found_ranks = set([c.rank_int for c in builder._cards])
    if found_ranks != allowed_ranks:
        raise ValueError(
            f"Texas Hold'em preflop lossless abstraction requires full deck with "
            f"ranks 2-A. What was specified={found_ranks} doesn't equal what is "
            f"allowed={allowed_ranks}"
        )
    
    # Getting combos and indexing with lossless abstraction
    preflop_lossless: Dict[Tuple[Card, Card], int] = {}
    for starting_hand in builder.starting_hands:
        starting_hand = sorted(
            list(starting_hand),
            key=operator.attrgetter("eval_card"),
            reverse=True
        )
        preflop_lossless[tuple(starting_hand)] = make_texas_holdem_starting_hand_lossless(
            starting_hand
        )
    return preflop_lossless


def get_preflop_clusters_texas_holdem() -> Dict[int, str]:
    """Get human-readable descriptions of the 169 preflop clusters.
    
    Returns a mapping from cluster ID to hand description.
    """
    clusters = {}
    cluster_id = 0
    
    # Pocket pairs (13 total)
    for rank in range(14, 1, -1):
        rank_str = {14: 'A', 13: 'K', 12: 'Q', 11: 'J', 10: 'T'}.get(rank, str(rank))
        clusters[cluster_id] = f"{rank_str}{rank_str}"
        cluster_id += 1
    
    # Non-pairs (suited and unsuited)
    for high_rank in range(14, 2, -1):
        for low_rank in range(high_rank - 1, 1, -1):
            high_str = {14: 'A', 13: 'K', 12: 'Q', 11: 'J', 10: 'T'}.get(high_rank, str(high_rank))
            low_str = {14: 'A', 13: 'K', 12: 'Q', 11: 'J', 10: 'T'}.get(low_rank, str(low_rank))
            
            # Suited
            clusters[cluster_id] = f"{high_str}{low_str}s"
            cluster_id += 1
            
            # Unsuited
            clusters[cluster_id] = f"{high_str}{low_str}o"
            cluster_id += 1
    
    return clusters