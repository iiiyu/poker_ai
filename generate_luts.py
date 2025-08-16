#!/usr/bin/env python3
"""
Generate card lookup tables (LUTs) for Texas Hold'em.
This pre-computes hand clusters to make the AI smarter.
"""

import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)


def generate_minimal_luts():
    """Generate minimal LUTs for quick testing."""
    
    print("\n" + "="*60)
    print("GENERATING MINIMAL CARD LOOKUP TABLES")
    print("="*60)
    print("\nThis creates hand clustering data for smarter AI training.")
    print("Options:")
    print("  1. Skip (fastest, weaker AI)")
    print("  2. Minimal (5 min, basic clustering)")
    print("  3. Full (hours/days, best AI)")
    print("\nGenerating MINIMAL luts...")
    print("="*60 + "\n")
    
    from poker_ai.clustering.card_info_lut_builder_extended import CardInfoLutBuilderExtended
    
    # Create builder with minimal settings for speed
    builder = CardInfoLutBuilderExtended(
        # Use very small simulation counts for speed
        n_simulations_river=10,    # normally 1000+
        n_simulations_turn=10,     # normally 1000+
        n_simulations_flop=10,     # normally 1000+
        n_simulations_preflop=10,  # normally 1000+
        # Texas Hold'em configuration
        low_card_rank=2,  # 2
        high_card_rank=14, # Ace
        save_dir="./card_luts",
        deck_type="texas_holdem"
    )
    
    start_time = time.time()
    
    try:
        print("Building preflop clusters (169 unique starting hands)...")
        builder.build_preflop_lut()
        print("✓ Preflop complete")
        
        print("\nBuilding flop clusters (this may take a few minutes)...")
        builder.build_flop_lut()
        print("✓ Flop complete")
        
        print("\nBuilding turn clusters...")
        builder.build_turn_lut()
        print("✓ Turn complete")
        
        print("\nBuilding river clusters...")
        builder.build_river_lut()
        print("✓ River complete")
        
        elapsed = time.time() - start_time
        print(f"\n✅ LUTs generated in {elapsed:.1f} seconds!")
        print(f"Saved to: ./card_luts/")
        
        return True
        
    except Exception as e:
        print(f"\n❌ LUT generation failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def use_precomputed_luts():
    """Download or use pre-computed LUTs."""
    
    print("\n" + "="*60)
    print("USING PRE-COMPUTED LUTS")
    print("="*60)
    
    # Check if LUTs already exist
    lut_files = [
        "card_luts/preflop_lut.pkl",
        "card_luts/flop_lut.pkl", 
        "card_luts/turn_lut.pkl",
        "card_luts/river_lut.pkl"
    ]
    
    existing = [f for f in lut_files if Path(f).exists()]
    
    if len(existing) == 4:
        print("✅ All LUT files already exist!")
        print("Files found:")
        for f in existing:
            size_mb = Path(f).stat().st_size / (1024*1024)
            print(f"  - {f} ({size_mb:.2f} MB)")
        return True
    
    print(f"Found {len(existing)}/4 LUT files")
    print("\nTo use pre-computed LUTs, you can:")
    print("1. Generate them: python generate_luts.py")
    print("2. Download them (if available)")
    print("3. Train without them (weaker but faster)")
    
    return False


def main():
    """Main function."""
    
    import sys
    
    print("\n🎯 CARD LOOKUP TABLE GENERATOR")
    print("="*60)
    print("\nLUTs make the AI understand hand strength better.")
    print("Without LUTs: All hands look the same (weaker AI)")
    print("With LUTs: AA > 72o (stronger AI)")
    print("\nOptions:")
    print("  1. Skip LUTs (train immediately, weaker AI)")
    print("  2. Generate minimal LUTs (5-10 minutes, better AI)")
    print("  3. Check for existing LUTs")
    
    if "--check" in sys.argv:
        return 0 if use_precomputed_luts() else 1
    
    if "--skip" in sys.argv:
        print("\n⚠️  Skipping LUT generation. AI will be weaker but trains faster.")
        return 0
    
    # Default: generate minimal LUTs
    print("\nGenerating minimal LUTs for better AI performance...")
    print("(Press Ctrl+C to skip)\n")
    
    success = generate_minimal_luts()
    
    if success:
        print("\n" + "="*60)
        print("NEXT STEPS")
        print("="*60)
        print("\nNow train with LUTs for a smarter agent:")
        print("  ./quick_train.sh small")
        print("\nOr train without LUTs (use --pickle_dir False):")
        print("  ./quick_train.sh quick")
        print("="*60 + "\n")
    
    return 0 if success else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  LUT generation skipped by user")
        print("You can train without LUTs using: ./quick_train.sh quick")
        sys.exit(0)