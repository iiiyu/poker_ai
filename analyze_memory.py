import numpy as np
from itertools import combinations

def calculate_memory_usage():
    """Calculate memory usage for LUT generation"""
    
    # Card deck parameters
    suits = 4
    ranks = 13  # 2-14 (2 through Ace)
    total_cards = suits * ranks  # 52 cards
    
    # Calculate combinations
    starting_hands = combinations(range(total_cards), 2)
    starting_hands_count = sum(1 for _ in starting_hands)
    
    board_3 = sum(1 for _ in combinations(range(total_cards), 3))
    board_4 = sum(1 for _ in combinations(range(total_cards), 4))
    board_5 = sum(1 for _ in combinations(range(total_cards), 5))
    
    print("Card Combinations:")
    print(f"  Starting hands (2 cards): {starting_hands_count:,}")
    print(f"  Board combinations (3 cards): {board_3:,}")
    print(f"  Board combinations (4 cards): {board_4:,}")
    print(f"  Board combinations (5 cards): {board_5:,}")
    print()
    
    # Calculate info combos (hand + board without conflicts)
    # These are approximations based on the actual logic
    flop_combos = starting_hands_count * board_3
    turn_combos = starting_hands_count * board_4
    river_combos = starting_hands_count * board_5
    
    # Actual values are less due to conflict filtering
    # Approximate reduction factor
    reduction = (total_cards - 2) * (total_cards - 3) * (total_cards - 4) / (total_cards * (total_cards - 1) * (total_cards - 2))
    flop_combos = int(flop_combos * reduction * (total_cards - 5) / total_cards)
    
    reduction = (total_cards - 2) * (total_cards - 3) * (total_cards - 4) * (total_cards - 5) / (total_cards * (total_cards - 1) * (total_cards - 2) * (total_cards - 3))
    turn_combos = int(turn_combos * reduction * (total_cards - 6) / total_cards)
    
    reduction = (total_cards - 2) * (total_cards - 3) * (total_cards - 4) * (total_cards - 5) * (total_cards - 6) / (total_cards * (total_cards - 1) * (total_cards - 2) * (total_cards - 3) * (total_cards - 4))
    river_combos = int(river_combos * reduction * (total_cards - 7) / total_cards)
    
    print("Info Combinations (approx):")
    print(f"  Flop (2+3 cards): ~{flop_combos:,}")
    print(f"  Turn (2+4 cards): ~{turn_combos:,}")
    print(f"  River (2+5 cards): ~{river_combos:,}")
    print()
    
    # Memory calculations for high mode (500 clusters, 20 simulations)
    print("Memory Usage Estimates (HIGH mode - 500 clusters, 20 simulations):")
    print()
    
    # River stage
    river_ehs_size = river_combos * 3 * 8  # 3 floats (win/loss/tie) * 8 bytes
    river_clusters_size = river_combos * 8  # cluster assignments
    river_lookup_size = river_combos * (7 * 8 + 8)  # tuple keys + int values
    river_total = river_ehs_size + river_clusters_size + river_lookup_size
    print(f"River Stage:")
    print(f"  EHS array: {river_ehs_size / 1024**3:.2f} GB")
    print(f"  Clusters: {river_clusters_size / 1024**3:.2f} GB")
    print(f"  Lookup table: {river_lookup_size / 1024**3:.2f} GB")
    print(f"  Total: {river_total / 1024**3:.2f} GB")
    print()
    
    # Turn stage
    turn_distribution_size = turn_combos * 500 * 8  # 500 river clusters
    turn_clusters_size = turn_combos * 8
    turn_lookup_size = turn_combos * (6 * 8 + 8)
    turn_total = turn_distribution_size + turn_clusters_size + turn_lookup_size
    print(f"Turn Stage:")
    print(f"  Distributions array: {turn_distribution_size / 1024**3:.2f} GB")
    print(f"  Clusters: {turn_clusters_size / 1024**3:.2f} GB")
    print(f"  Lookup table: {turn_lookup_size / 1024**3:.2f} GB")
    print(f"  Total: {turn_total / 1024**3:.2f} GB")
    print()
    
    # Flop stage
    flop_distribution_size = flop_combos * 500 * 8  # 500 turn clusters
    flop_clusters_size = flop_combos * 8
    flop_lookup_size = flop_combos * (5 * 8 + 8)
    flop_total = flop_distribution_size + flop_clusters_size + flop_lookup_size
    print(f"Flop Stage:")
    print(f"  Distributions array: {flop_distribution_size / 1024**3:.2f} GB")
    print(f"  Clusters: {flop_clusters_size / 1024**3:.2f} GB")
    print(f"  Lookup table: {flop_lookup_size / 1024**3:.2f} GB")
    print(f"  Total: {flop_total / 1024**3:.2f} GB")
    print()
    
    # Peak memory (worst case - during turn processing with river data still in memory)
    peak_memory = river_total + turn_total
    print(f"Peak Memory Usage (Turn stage): {peak_memory / 1024**3:.2f} GB")
    print()
    
    # With multiprocessing overhead (roughly 2x for worker processes)
    print(f"With multiprocessing overhead (~2x): {peak_memory * 2 / 1024**3:.2f} GB")

if __name__ == "__main__":
    calculate_memory_usage()
