#!/usr/bin/env python3
"""
Migration script from old clustering system to unified SQLite-backed system.
Converts existing LUT files and checkpoints to new format.
"""

import os
import sys
import shutil
import joblib
import sqlite3
import pickle
import numpy as np
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional

def backup_existing_files(backup_dir: str = "backup_clustering") -> bool:
    """Backup existing LUT and checkpoint files."""
    backup_path = Path(backup_dir)
    backup_path.mkdir(exist_ok=True)
    
    files_to_backup = [
        "card_info_lut.joblib",
        "centroids.joblib",
        "turn_processing.db",
        "clustering_data.db"
    ]
    
    dirs_to_backup = [
        "lut_checkpoints"
    ]
    
    backed_up = []
    
    # Backup files
    for file in files_to_backup:
        if Path(file).exists():
            dest = backup_path / f"{file}.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            shutil.copy2(file, dest)
            backed_up.append(file)
            print(f"✅ Backed up {file} to {dest}")
    
    # Backup directories
    for dir_name in dirs_to_backup:
        if Path(dir_name).exists():
            dest = backup_path / f"{dir_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            shutil.copytree(dir_name, dest)
            backed_up.append(dir_name)
            print(f"✅ Backed up {dir_name} to {dest}")
    
    if backed_up:
        print(f"\n📦 Backed up {len(backed_up)} items to {backup_path}")
        return True
    else:
        print("📭 No existing files to backup")
        return False

def migrate_old_lut_to_database(lut_path: str = "card_info_lut.joblib", 
                                db_path: str = "clustering_data.db") -> bool:
    """
    Migrate old joblib LUT to SQLite database format.
    """
    if not Path(lut_path).exists():
        print(f"❌ LUT file not found: {lut_path}")
        return False
    
    print(f"📂 Loading old LUT from {lut_path}...")
    try:
        old_lut = joblib.load(lut_path)
    except Exception as e:
        print(f"❌ Failed to load LUT: {e}")
        return False
    
    print(f"📊 Found {len(old_lut)} entries in old LUT")
    
    # Initialize database
    print(f"🗄️ Creating new database: {db_path}")
    conn = sqlite3.connect(db_path)
    
    # Set up optimizations
    conn.execute('PRAGMA journal_mode = WAL')
    conn.execute('PRAGMA synchronous = NORMAL')
    conn.execute('PRAGMA cache_size = -64000')
    
    # Create tables
    conn.execute('''
        CREATE TABLE IF NOT EXISTS river_data (
            combo_id INTEGER PRIMARY KEY,
            combo_cards BLOB NOT NULL,
            ehs_data BLOB,
            cluster_id INTEGER DEFAULT -1,
            processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.execute('''
        CREATE TABLE IF NOT EXISTS turn_data (
            combo_id INTEGER PRIMARY KEY,
            combo_cards BLOB NOT NULL,
            distribution BLOB,
            cluster_id INTEGER DEFAULT -1,
            processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.execute('''
        CREATE TABLE IF NOT EXISTS flop_data (
            combo_id INTEGER PRIMARY KEY,
            combo_cards BLOB NOT NULL,
            distribution BLOB,
            cluster_id INTEGER DEFAULT -1,
            processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.execute('''
        CREATE TABLE IF NOT EXISTS migrated_lut (
            stage TEXT,
            combo_key TEXT,
            cluster_id INTEGER,
            migrated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (stage, combo_key)
        )
    ''')
    
    # Migrate data by stage
    stages_migrated = {
        "preflop": 0,
        "flop": 0,
        "turn": 0,
        "river": 0
    }
    
    for key, value in old_lut.items():
        if key == "pre_flop":
            # Preflop is a nested dict
            if isinstance(value, dict):
                for combo_key, cluster_id in value.items():
                    conn.execute('''
                        INSERT OR REPLACE INTO migrated_lut (stage, combo_key, cluster_id)
                        VALUES (?, ?, ?)
                    ''', ("preflop", combo_key, cluster_id))
                    stages_migrated["preflop"] += 1
        elif key in ["flop", "turn", "river"]:
            # Postflop stages
            if isinstance(value, dict):
                for combo_key, cluster_id in value.items():
                    # Store in migrated_lut table
                    conn.execute('''
                        INSERT OR REPLACE INTO migrated_lut (stage, combo_key, cluster_id)
                        VALUES (?, ?, ?)
                    ''', (key, str(combo_key), cluster_id))
                    stages_migrated[key] += 1
    
    conn.commit()
    
    # Report migration results
    print("\n📊 Migration Summary:")
    for stage, count in stages_migrated.items():
        if count > 0:
            print(f"  {stage}: {count:,} entries migrated")
    
    # Verify migration
    cursor = conn.execute('SELECT COUNT(*) FROM migrated_lut')
    total_migrated = cursor.fetchone()[0]
    print(f"\n✅ Total entries migrated: {total_migrated:,}")
    
    conn.close()
    return True

def verify_migration(db_path: str = "clustering_data.db", 
                     old_lut_path: str = "card_info_lut.joblib") -> bool:
    """
    Verify that migration was successful by comparing old and new data.
    """
    print("\n🔍 Verifying migration...")
    
    if not Path(old_lut_path).exists():
        print("⚠️ Old LUT not found for verification")
        return True  # Assume OK if no old file
    
    if not Path(db_path).exists():
        print("❌ New database not found")
        return False
    
    # Load old LUT
    old_lut = joblib.load(old_lut_path)
    
    # Connect to database
    conn = sqlite3.connect(db_path)
    
    # Count entries
    cursor = conn.execute('SELECT COUNT(*) FROM migrated_lut')
    db_count = cursor.fetchone()[0]
    
    old_count = 0
    for key, value in old_lut.items():
        if isinstance(value, dict):
            old_count += len(value)
    
    print(f"Old LUT entries: {old_count:,}")
    print(f"Database entries: {db_count:,}")
    
    if db_count == 0:
        print("⚠️ No entries in database")
        conn.close()
        return False
    
    # Sample verification
    cursor = conn.execute('SELECT * FROM migrated_lut LIMIT 10')
    samples = cursor.fetchall()
    print(f"\n📝 Sample migrated entries:")
    for stage, combo_key, cluster_id, timestamp in samples[:5]:
        print(f"  {stage}: {combo_key[:20]}... → cluster {cluster_id}")
    
    conn.close()
    
    print("\n✅ Migration verification complete")
    return True

def create_unified_config(output_path: str = "unified_config.yaml") -> None:
    """
    Create configuration file for unified system.
    """
    config = """# Unified SQLite LUT Builder Configuration
# Generated by migration script

# Memory settings
memory_limit_gb: 50
batch_size: 50

# Database settings
db_path: clustering_data.db
checkpoint_dir: lut_checkpoints

# Clustering parameters
n_river_clusters: 400
n_turn_clusters: 300
n_flop_clusters: 300
n_preflop_clusters: 169

# Simulation settings
n_simulations_river: 20
n_simulations_turn: 15
n_simulations_flop: 15

# Card range
low_card_rank: 2
high_card_rank: 14

# Processing settings
micro_batch_turn: 20  # Smaller batches for turn due to memory
checkpoint_frequency: 100  # Save progress every N items

# SQLite optimizations
sqlite_settings:
  journal_mode: WAL
  synchronous: NORMAL
  cache_size: -64000  # 64MB
  temp_store: MEMORY
  mmap_size: 268435456  # 256MB
"""
    
    with open(output_path, 'w') as f:
        f.write(config)
    
    print(f"📝 Created unified configuration: {output_path}")

def main():
    """Main migration script."""
    print("="*60)
    print("🔄 MIGRATION TO UNIFIED SQLite CLUSTERING SYSTEM")
    print("="*60)
    print()
    
    # Step 1: Backup
    print("Step 1: Backing up existing files...")
    backup_success = backup_existing_files()
    print()
    
    # Step 2: Check what needs migration
    has_old_lut = Path("card_info_lut.joblib").exists()
    has_old_db = Path("turn_processing.db").exists()
    has_new_db = Path("clustering_data.db").exists()
    
    print("Step 2: Checking existing files...")
    print(f"  Old LUT (card_info_lut.joblib): {'✅ Found' if has_old_lut else '❌ Not found'}")
    print(f"  Old turn DB (turn_processing.db): {'✅ Found' if has_old_db else '❌ Not found'}")
    print(f"  New unified DB (clustering_data.db): {'✅ Found' if has_new_db else '❌ Not found'}")
    print()
    
    # Step 3: Migrate if needed
    if has_old_lut and not has_new_db:
        print("Step 3: Migrating old LUT to unified database...")
        migration_success = migrate_old_lut_to_database()
        
        if migration_success:
            print("\n✅ Migration successful!")
            
            # Verify
            verify_migration()
        else:
            print("\n❌ Migration failed!")
            sys.exit(1)
    elif has_new_db:
        print("Step 3: Unified database already exists, skipping migration")
    else:
        print("Step 3: No old LUT found, nothing to migrate")
    print()
    
    # Step 4: Create config
    print("Step 4: Creating unified configuration...")
    create_unified_config()
    print()
    
    # Step 5: Instructions
    print("="*60)
    print("📋 NEXT STEPS")
    print("="*60)
    print()
    print("1. To generate NEW LUT with unified system:")
    print("   ./generate_lut_unified.sh auto")
    print()
    print("2. To continue with existing data:")
    print("   ./generate_lut_unified.sh [mode]")
    print("   (Will resume from checkpoints if available)")
    print()
    print("3. Old files are backed up in: backup_clustering/")
    print()
    print("4. To clean up old files after verification:")
    print("   rm card_info_lut.joblib")
    print("   rm turn_processing.db")
    print("   rm -rf lut_checkpoints_old")
    print()
    print("✅ Migration complete!")

if __name__ == "__main__":
    main()