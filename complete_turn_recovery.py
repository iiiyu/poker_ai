#!/usr/bin/env python3
"""
Emergency recovery script to complete remaining turn combinations after OOM failure.
This script processes the remaining 2% of turn combinations with minimal memory usage.
"""

import os
import sys
import sqlite3
import numpy as np
import gc
import psutil
from pathlib import Path
from tqdm import tqdm

sys.path.insert(0, '.')

from poker_ai.clustering.unified_sqlite_builder import UnifiedSQLiteLUTBuilder
from poker_ai.poker.evaluation import Evaluator
from poker_ai.clustering.card_combos import CardCombos
import pickle
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_memory_usage():
    """Get current memory usage in GB."""
    process = psutil.Process()
    return process.memory_info().rss / (1024 ** 3)

def check_database_progress(db_path):
    """Check how many turn combinations have been processed."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Check turn_data table
    cursor.execute("SELECT COUNT(*) FROM turn_data WHERE distribution IS NOT NULL")
    processed = cursor.fetchone()[0]
    
    # Get total expected
    cursor.execute("SELECT COUNT(DISTINCT combo) FROM turn_data")
    total = cursor.fetchone()[0]
    
    conn.close()
    return processed, total

def find_missing_combos(db_path):
    """Find which turn combinations haven't been processed."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Find combos with NULL distribution
    cursor.execute("""
        SELECT DISTINCT combo 
        FROM turn_data 
        WHERE distribution IS NULL
        ORDER BY combo
    """)
    
    missing = [row[0] for row in cursor.fetchall()]
    conn.close()
    return missing

def process_single_combo(builder, combo_idx, evaluator, batch_size=1):
    """Process a single turn combination with minimal memory."""
    logger.info(f"Processing combo {combo_idx} with batch_size={batch_size}")
    
    # Generate combos for this specific index
    combo_gen = CardCombos()
    
    turn_combos = list(combo_gen.get_turn_combos())
    
    if combo_idx >= len(turn_combos):
        logger.error(f"Combo index {combo_idx} out of range (max: {len(turn_combos)-1})")
        return False
    
    target_combo = turn_combos[combo_idx]
    
    # Clear memory before processing
    gc.collect()
    
    try:
        # Process with minimal batch size
        conn = sqlite3.connect(builder.db_path)
        cursor = conn.cursor()
        
        # Check if already processed
        cursor.execute(
            "SELECT distribution FROM turn_data WHERE combo = ? AND distribution IS NOT NULL LIMIT 1",
            (combo_idx,)
        )
        if cursor.fetchone():
            logger.info(f"Combo {combo_idx} already processed, skipping")
            conn.close()
            return True
        
        # Get distributions for this combo
        cursor.execute(
            "SELECT river_idx, distribution FROM turn_data WHERE combo = ?",
            (combo_idx,)
        )
        rows = cursor.fetchall()
        
        if not rows:
            logger.warning(f"No data found for combo {combo_idx}, generating...")
            # Generate the data if missing
            builder._process_turn_batch([combo_idx], batch_size=batch_size)
            return True
        
        # Process distributions
        distributions = []
        for river_idx, dist_blob in rows:
            if dist_blob is None:
                # Generate distribution for this river
                river_cards = builder._get_river_cards(target_combo, river_idx)
                dist = builder._calculate_distribution(target_combo, river_cards, evaluator)
                distributions.append(dist)
            else:
                distributions.append(pickle.loads(dist_blob))
        
        # Update database
        for i, dist in enumerate(distributions):
            if rows[i][1] is None:  # Only update NULL entries
                cursor.execute(
                    "UPDATE turn_data SET distribution = ? WHERE combo = ? AND river_idx = ?",
                    (pickle.dumps(dist), combo_idx, i)
                )
        
        conn.commit()
        conn.close()
        
        logger.info(f"Successfully processed combo {combo_idx}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to process combo {combo_idx}: {e}")
        return False
    finally:
        gc.collect()

def complete_recovery(db_path='clustering_data.db', memory_limit_gb=3.0):
    """Complete the remaining turn combinations with minimal memory usage."""
    
    logger.info("=" * 60)
    logger.info("TURN COMBINATION RECOVERY SCRIPT")
    logger.info("=" * 60)
    
    # Check current progress
    processed, total = check_database_progress(db_path)
    logger.info(f"Database progress: {processed}/{total} combinations processed ({processed/total*100:.1f}%)")
    
    if processed >= total:
        logger.info("✅ All turn combinations already processed!")
        return True
    
    # Find missing combos
    missing = find_missing_combos(db_path)
    logger.info(f"Found {len(missing)} missing combinations: {missing[:5]}{'...' if len(missing) > 5 else ''}")
    
    # Initialize builder with minimal settings
    logger.info("Initializing builder with emergency settings...")
    builder = UnifiedSQLiteLUTBuilder(
        n_simulations_river=100,  # Minimal simulations
        n_simulations_turn=100,
        n_simulations_flop=100,
        low_card_rank=2,
        high_card_rank=14,
        save_dir='.',
        n_river_clusters=10,
        n_turn_clusters=50,
        n_flop_clusters=150,
        memory_limit_gb=memory_limit_gb,
        batch_size=1,  # Process one at a time
        db_path=db_path,
        checkpoint_dir='lut_checkpoints'
    )
    
    evaluator = Evaluator()
    
    # Process each missing combo
    success_count = 0
    for i, combo_idx in enumerate(tqdm(missing, desc="Processing missing combos")):
        memory = get_memory_usage()
        if memory > memory_limit_gb * 0.8:
            logger.warning(f"Memory usage high ({memory:.1f}GB), forcing cleanup...")
            gc.collect()
            
            # If still high, use even smaller batch
            if get_memory_usage() > memory_limit_gb * 0.8:
                logger.warning("Using emergency single-item processing...")
                batch_size = 1
            else:
                batch_size = 2
        else:
            batch_size = 5
        
        if process_single_combo(builder, combo_idx, evaluator, batch_size):
            success_count += 1
        else:
            logger.error(f"Failed to process combo {combo_idx}")
        
        # Periodic cleanup
        if i % 10 == 0:
            gc.collect()
    
    logger.info(f"Recovery complete: {success_count}/{len(missing)} combos processed successfully")
    
    # Final check
    processed, total = check_database_progress(db_path)
    logger.info(f"Final progress: {processed}/{total} ({processed/total*100:.1f}%)")
    
    if processed >= total:
        logger.info("✅ All turn combinations now processed!")
        logger.info("You can now run the finalization step to create the LUT file")
        return True
    else:
        logger.warning(f"⚠️ Still missing {total - processed} combinations")
        return False

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Complete turn combination processing after OOM")
    parser.add_argument('--db', default='clustering_data.db', help='Database path')
    parser.add_argument('--memory', type=float, default=3.0, help='Memory limit in GB')
    args = parser.parse_args()
    
    success = complete_recovery(args.db, args.memory)
    sys.exit(0 if success else 1)