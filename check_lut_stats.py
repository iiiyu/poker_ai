#!/usr/bin/env python3
"""
Check statistics about card combinations for different deck sizes.
"""

from itertools import combinations
import math

def calculate_combinations(low_rank, high_rank):
    """Calculate the number of combinations for each betting round."""
    n_ranks = high_rank - low_rank + 1
    n_cards = n_ranks * 4  # 4 suits per rank
    
    print(f"\nDeck Configuration:")
    print(f"  Ranks: {low_rank} to {high_rank}")
    print(f"  Number of ranks: {n_ranks}")
    print(f"  Total cards: {n_cards}")
    
    # Preflop: 2 hole cards
    preflop_combos = math.comb(n_cards, 2)
    
    # River: 2 hole cards + 5 community cards
    river_combos = math.comb(n_cards, 7)
    
    # Turn: 2 hole cards + 4 community cards  
    turn_combos = math.comb(n_cards, 6)
    
    # Flop: 2 hole cards + 3 community cards
    flop_combos = math.comb(n_cards, 5)
    
    print(f"\nCombination Counts:")
    print(f"  Preflop (2 cards): {preflop_combos:,}")
    print(f"  Flop (5 cards): {flop_combos:,}")
    print(f"  Turn (6 cards): {turn_combos:,}")
    print(f"  River (7 cards): {river_combos:,}")
    
    # Estimate memory usage (rough)
    # Assume each entry takes ~100 bytes (cluster ID + metadata)
    bytes_per_entry = 100
    total_entries = preflop_combos + flop_combos + turn_combos + river_combos
    estimated_size_mb = (total_entries * bytes_per_entry) / (1024 * 1024)
    
    print(f"\nEstimated LUT size: {estimated_size_mb:.1f} MB")
    print(f"  (assuming {bytes_per_entry} bytes per entry)")
    
    return {
        'n_cards': n_cards,
        'preflop': preflop_combos,
        'flop': flop_combos,
        'turn': turn_combos,
        'river': river_combos,
        'total': total_entries,
        'size_mb': estimated_size_mb
    }

def main():
    print("="*60)
    print("CARD COMBINATION STATISTICS")
    print("="*60)
    
    # Short deck (what you have now)
    print("\n1. SHORT DECK (Current)")
    short_deck = calculate_combinations(10, 14)
    
    # Medium deck
    print("\n2. MEDIUM DECK")
    medium_deck = calculate_combinations(6, 14)
    
    # Full deck (Texas Hold'em standard)
    print("\n3. FULL DECK (Texas Hold'em)")
    full_deck = calculate_combinations(2, 14)
    
    # Comparison
    print("\n" + "="*60)
    print("COMPARISON")
    print("="*60)
    
    print(f"\nSize increase from short to full deck:")
    print(f"  Combinations: {full_deck['total']/short_deck['total']:.1f}x larger")
    print(f"  Estimated size: {full_deck['size_mb']/short_deck['size_mb']:.1f}x larger")
    
    print(f"\nYour current 70MB file suggests:")
    print(f"  - You're using short deck (20 cards)")
    print(f"  - With 50 clusters per stage")
    print(f"  - Low simulation count (6)")
    
    print(f"\nFor full Texas Hold'em, expect:")
    print(f"  - File size: 200-500MB (with 200 clusters)")
    print(f"  - Generation time: 2-4 hours")
    print(f"  - Much better strategy quality")
    
    # Check if current LUT exists
    import os
    if os.path.exists('card_info_lut.joblib'):
        import joblib
        try:
            lut = joblib.load('card_info_lut.joblib')
            if isinstance(lut, dict):
                print(f"\n" + "="*60)
                print("CURRENT LUT ANALYSIS")
                print("="*60)
                for stage, entries in lut.items():
                    if isinstance(entries, dict):
                        print(f"{stage}: {len(entries):,} entries")
        except:
            print("\nCouldn't analyze current LUT file")

if __name__ == "__main__":
    main()