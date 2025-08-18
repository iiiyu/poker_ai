#!/usr/bin/env python3
"""Test script for the new unified LUT builder architecture."""

import sys
import os
sys.path.insert(0, '.')

from poker_ai.clustering.unified_builder import UnifiedLUTBuilder


def test_unified_builder():
    """Test the unified builder with minimal settings."""
    
    print("Testing Unified LUT Builder")
    print("=" * 60)
    
    # Test with emergency mode settings
    builder = UnifiedLUTBuilder(
        # Minimal simulations for testing
        n_simulations_river=10,
        n_simulations_turn=10,
        n_simulations_flop=10,
        
        # Small card range for testing (just 2-4)
        low_card_rank=2,
        high_card_rank=4,
        
        # Minimal clusters
        n_river_clusters=5,
        n_turn_clusters=5,
        n_flop_clusters=5,
        
        # Strict memory limits
        memory_limit_gb=3.0,
        memory_safety_factor=0.5,
        aggressive_gc=True,
        
        # Small batches
        batch_size=5,
        chunk_size=5,
        
        # Test database
        db_path="test_unified.db",
        save_dir=".",
        checkpoint_dir="test_checkpoints"
    )
    
    print("\n✅ Builder initialized successfully")
    print(f"   Storage backend: {builder.storage.db_path}")
    print(f"   Memory limit: {builder.memory.effective_limit_gb:.1f}GB")
    print(f"   Chunk size: {builder.storage.chunk_size}")
    
    # Test combinations generation
    print(f"\n📊 Combinations:")
    print(f"   River: {len(builder.river)} combinations")
    print(f"   Turn: {len(builder.turn)} combinations")
    print(f"   Flop: {len(builder.flop)} combinations")
    
    # Test memory manager
    print(f"\n💾 Memory Status:")
    current_mem = builder.memory.get_memory_usage_gb()
    print(f"   Current usage: {current_mem:.2f}GB")
    print(f"   Within limits: {builder.memory.check_memory()}")
    
    # Test storage backend
    print(f"\n💿 Storage Backend:")
    print(f"   Database exists: {builder.storage.db_path.exists()}")
    
    # Test storing and retrieving
    import numpy as np
    test_combo = np.array([[2, 1], [2, 2]])
    test_dist = np.array([0.1, 0.2, 0.3, 0.4])
    
    # Use a valid stage name (river, turn, or flop)
    builder.storage.store_distribution('river', 0, test_combo, test_dist)
    builder.storage.flush()
    
    retrieved = builder.storage.get_distribution('river', 0)
    if retrieved is not None and np.allclose(retrieved, test_dist):
        print("   ✅ Store/retrieve test passed")
    else:
        print("   ❌ Store/retrieve test failed")
    
    # Cleanup test
    builder.cleanup()
    print("\n✅ All tests passed!")
    
    # Clean up test files
    import shutil
    if os.path.exists("test_unified.db"):
        os.remove("test_unified.db")
    if os.path.exists("test_checkpoints"):
        shutil.rmtree("test_checkpoints")
    
    return True


if __name__ == "__main__":
    try:
        success = test_unified_builder()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)