#!/usr/bin/env python3
"""
Diagnostic tool to analyze memory requirements and recommend optimal settings
for poker AI LUT generation.
"""

import os
import sys
import psutil
import numpy as np
from itertools import combinations
from typing import Dict, Tuple
import yaml


def get_system_info() -> Dict:
    """Get system memory and CPU information."""
    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()
    
    return {
        'total_ram_gb': mem.total / (1024**3),
        'available_ram_gb': mem.available / (1024**3),
        'used_ram_gb': mem.used / (1024**3),
        'ram_percent': mem.percent,
        'swap_total_gb': swap.total / (1024**3),
        'swap_used_gb': swap.used / (1024**3),
        'cpu_count': os.cpu_count() or 4,
        'cpu_freq': psutil.cpu_freq().current if psutil.cpu_freq() else 0
    }


def calculate_combinations(low_rank: int = 2, high_rank: int = 14) -> Dict:
    """Calculate the number of card combinations for each stage."""
    suits = 4
    ranks = high_rank - low_rank + 1
    total_cards = suits * ranks
    
    # Calculate exact combinations
    from math import comb
    n_starting_hands = comb(total_cards, 2)  # C(52,2) = 1326
    
    # For info sets, we need starting hands × board combinations
    # But excluding cards that conflict with hole cards
    # River: 2 hole + 5 board = 7 cards from 52
    # Turn: 2 hole + 4 board = 6 cards from 52  
    # Flop: 2 hole + 3 board = 5 cards from 52
    
    # More accurate estimates based on actual poker combinations
    # These account for the fact that board cards can't overlap with hole cards
    n_flop_combos = n_starting_hands * comb(total_cards - 2, 3)  # ~2.6M for Texas Hold'em
    n_turn_combos = n_starting_hands * comb(total_cards - 2, 4)  # ~270M for Texas Hold'em
    n_river_combos = n_starting_hands * comb(total_cards - 2, 5)  # ~2.5B for Texas Hold'em
    
    # Apply sampling reduction (we don't process ALL combinations)
    # The actual implementation samples a subset
    sampling_factor = 0.01  # Typically sample ~1% of combinations
    
    return {
        'total_cards': total_cards,
        'starting_hands': n_starting_hands,
        'flop_combos': int(n_flop_combos * sampling_factor),
        'turn_combos': int(n_turn_combos * sampling_factor),
        'river_combos': int(n_river_combos * sampling_factor)
    }


def estimate_memory_usage(
    combos: Dict,
    n_river_clusters: int,
    n_turn_clusters: int,
    n_flop_clusters: int
) -> Dict:
    """Estimate memory usage for given cluster settings."""
    
    # River stage memory
    river_ehs_size = combos['river_combos'] * 3 * 8  # 3 floats * 8 bytes
    river_clusters_size = combos['river_combos'] * 8  # cluster IDs
    river_lookup_size = combos['river_combos'] * (7 * 8 + 8)  # tuple keys + values
    river_total = river_ehs_size + river_clusters_size + river_lookup_size
    
    # Turn stage memory (the bottleneck!)
    turn_dist_size = combos['turn_combos'] * n_river_clusters * 8
    turn_clusters_size = combos['turn_combos'] * 8
    turn_lookup_size = combos['turn_combos'] * (6 * 8 + 8)
    turn_total = turn_dist_size + turn_clusters_size + turn_lookup_size
    
    # Flop stage memory
    flop_dist_size = combos['flop_combos'] * n_turn_clusters * 8
    flop_clusters_size = combos['flop_combos'] * 8
    flop_lookup_size = combos['flop_combos'] * (5 * 8 + 8)
    flop_total = flop_dist_size + flop_clusters_size + flop_lookup_size
    
    # Peak memory (during turn processing with river data still in memory)
    peak_memory = river_total + turn_total
    
    # With multiprocessing overhead (conservative estimate)
    peak_with_overhead = peak_memory * 1.5
    
    return {
        'river_gb': river_total / (1024**3),
        'turn_gb': turn_total / (1024**3),
        'flop_gb': flop_total / (1024**3),
        'peak_gb': peak_memory / (1024**3),
        'peak_with_overhead_gb': peak_with_overhead / (1024**3),
        'turn_dist_gb': turn_dist_size / (1024**3),  # The main bottleneck
    }


def find_optimal_settings(available_gb: float, combos: Dict) -> Dict:
    """Find optimal cluster settings for available memory."""
    
    # Target 80% of available memory
    target_gb = available_gb * 0.8
    
    # Start with high quality and reduce until it fits
    test_configs = [
        (500, 500, 500),
        (400, 400, 400),
        (350, 350, 350),
        (300, 300, 300),
        (250, 250, 250),
        (200, 200, 200),
        (150, 150, 150),
        (100, 100, 100),
        (50, 50, 50),
    ]
    
    best_config = None
    best_memory = 0
    
    for river_c, turn_c, flop_c in test_configs:
        mem = estimate_memory_usage(combos, river_c, turn_c, flop_c)
        if mem['peak_with_overhead_gb'] <= target_gb:
            best_config = (river_c, turn_c, flop_c)
            best_memory = mem['peak_with_overhead_gb']
            break
    
    # If even the smallest doesn't fit, calculate custom
    if best_config is None:
        # Calculate maximum possible with very small clusters
        max_river_clusters = min(50, int(target_gb / 10))
        max_turn_clusters = min(50, int(target_gb / 10))
        max_flop_clusters = min(50, int(target_gb / 10))
        best_config = (max_river_clusters, max_turn_clusters, max_flop_clusters)
        mem = estimate_memory_usage(combos, *best_config)
        best_memory = mem['peak_with_overhead_gb']
    
    return {
        'river_clusters': best_config[0],
        'turn_clusters': best_config[1],
        'flop_clusters': best_config[2],
        'estimated_memory_gb': best_memory,
        'memory_details': estimate_memory_usage(combos, *best_config)
    }


def print_diagnosis():
    """Print comprehensive memory diagnosis and recommendations."""
    
    print("=" * 70)
    print("POKER AI MEMORY DIAGNOSIS & OPTIMIZATION TOOL")
    print("=" * 70)
    print()
    
    # Get system info
    sys_info = get_system_info()
    
    print("SYSTEM INFORMATION")
    print("-" * 40)
    print(f"Total RAM:        {sys_info['total_ram_gb']:.1f} GB")
    print(f"Available RAM:    {sys_info['available_ram_gb']:.1f} GB ({100 - sys_info['ram_percent']:.1f}% free)")
    print(f"Used RAM:         {sys_info['used_ram_gb']:.1f} GB ({sys_info['ram_percent']:.1f}%)")
    print(f"Swap Space:       {sys_info['swap_total_gb']:.1f} GB total, {sys_info['swap_used_gb']:.1f} GB used")
    print(f"CPU Cores:        {sys_info['cpu_count']}")
    print()
    
    # Check for both deck types
    print("DATASET SIZES")
    print("-" * 40)
    
    # Texas Hold'em (52 cards)
    texas_combos = calculate_combinations(2, 14)
    print("Texas Hold'em (52 cards, ranks 2-A):")
    print(f"  River combinations:  {texas_combos['river_combos']:,}")
    print(f"  Turn combinations:   {texas_combos['turn_combos']:,}")
    print(f"  Flop combinations:   {texas_combos['flop_combos']:,}")
    print()
    
    # Short Deck (20 cards)
    short_combos = calculate_combinations(10, 14)
    print("Short Deck (20 cards, ranks 10-A):")
    print(f"  River combinations:  {short_combos['river_combos']:,}")
    print(f"  Turn combinations:   {short_combos['turn_combos']:,}")
    print(f"  Flop combinations:   {short_combos['flop_combos']:,}")
    print()
    
    # Memory analysis for different quality levels
    print("MEMORY REQUIREMENTS (Texas Hold'em)")
    print("-" * 40)
    
    quality_levels = [
        ("Low (100 clusters)", 100, 100, 100),
        ("Medium (200 clusters)", 200, 200, 200),
        ("High (300 clusters)", 300, 300, 300),
        ("Ultra (400/300/300)", 400, 300, 300),
        ("Max (500 clusters)", 500, 500, 500),
    ]
    
    for name, river_c, turn_c, flop_c in quality_levels:
        mem = estimate_memory_usage(texas_combos, river_c, turn_c, flop_c)
        status = "✓" if mem['peak_with_overhead_gb'] <= sys_info['available_ram_gb'] else "✗"
        print(f"{status} {name:20} Peak: {mem['peak_with_overhead_gb']:6.1f} GB")
        if name == "Ultra (400/300/300)":
            print(f"  {'':22} (Optimized for 50GB limit)")
    print()
    
    # Find optimal settings
    print("RECOMMENDED SETTINGS FOR YOUR SYSTEM")
    print("-" * 40)
    
    optimal = find_optimal_settings(sys_info['available_ram_gb'], texas_combos)
    
    print(f"Based on {sys_info['available_ram_gb']:.1f} GB available RAM:")
    print(f"  River clusters:     {optimal['river_clusters']}")
    print(f"  Turn clusters:      {optimal['turn_clusters']}")
    print(f"  Flop clusters:      {optimal['flop_clusters']}")
    print(f"  Estimated memory:   {optimal['estimated_memory_gb']:.1f} GB")
    print()
    
    # Quality assessment
    quality_score = min(optimal['river_clusters'], optimal['turn_clusters']) / 100
    if quality_score >= 5:
        quality = "★★★★★ Excellent"
    elif quality_score >= 4:
        quality = "★★★★☆ High"
    elif quality_score >= 3:
        quality = "★★★☆☆ Good"
    elif quality_score >= 2:
        quality = "★★☆☆☆ Medium"
    else:
        quality = "★☆☆☆☆ Low"
    
    print(f"Quality Rating: {quality}")
    print()
    
    # Bottleneck analysis
    print("MEMORY BOTTLENECK ANALYSIS")
    print("-" * 40)
    details = optimal['memory_details']
    print(f"River stage:        {details['river_gb']:.1f} GB")
    print(f"Turn stage:         {details['turn_gb']:.1f} GB")
    print(f"  - Distributions:  {details['turn_dist_gb']:.1f} GB (main bottleneck!)")
    print(f"Flop stage:         {details['flop_gb']:.1f} GB")
    print()
    
    # Recommendations
    print("RECOMMENDATIONS")
    print("-" * 40)
    
    if sys_info['available_ram_gb'] < 20:
        print("⚠️  WARNING: Limited memory available!")
        print("   - Close unnecessary applications")
        print("   - Use 'low' quality mode")
        print("   - Consider using a cloud instance with more RAM")
    elif sys_info['available_ram_gb'] < 40:
        print("✓ Sufficient memory for medium quality")
        print("   - Use 'medium' or 'high' quality mode")
        print("   - The process will use disk caching for safety")
    elif sys_info['available_ram_gb'] < 60:
        print("✓ Good memory for high quality")
        print("   - Use 'high' quality mode for best results")
        print("   - 'ultra' mode may work but will be tight")
    else:
        print("✓ Excellent memory availability!")
        print("   - Use 'ultra' mode for maximum quality")
        print("   - Consider the professional settings if you have 100GB+")
    
    print()
    print("SUGGESTED COMMAND")
    print("-" * 40)
    
    if sys_info['available_ram_gb'] >= 45:
        print("./generate_lut_memory_safe.sh ultra")
    elif sys_info['available_ram_gb'] >= 35:
        print("./generate_lut_memory_safe.sh high")
    elif sys_info['available_ram_gb'] >= 25:
        print("./generate_lut_memory_safe.sh medium")
    else:
        print("./generate_lut_memory_safe.sh low")
    
    print()
    print("For custom settings based on this analysis:")
    print("./generate_lut_memory_safe.sh custom")
    print(f"  Then enter: {optimal['river_clusters']} / {optimal['turn_clusters']} / {optimal['flop_clusters']} clusters")
    print()
    
    # Check for existing files
    if os.path.exists("card_info_lut.joblib"):
        print("NOTE: Existing LUT file found!")
        print("      The process will resume from checkpoint if interrupted.")
        print("      Use --force to regenerate from scratch.")
        print()


if __name__ == "__main__":
    try:
        print_diagnosis()
    except ImportError as e:
        print(f"Error: Missing required package: {e}")
        print("Install with: pip install psutil pyyaml numpy")
        sys.exit(1)