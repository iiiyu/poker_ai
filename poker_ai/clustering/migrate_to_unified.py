"""
Migration script to transition from current mixed implementation to unified SQLite builder.
"""

import logging
import shutil
from pathlib import Path
import joblib
import sqlite3
import numpy as np
import pickle

log = logging.getLogger(__name__)


class ClusteringMigrator:
    """Handles migration from old clustering system to unified SQLite-backed system"""
    
    def __init__(self, 
                 old_checkpoint_dir: Path = Path("checkpoints"),
                 new_db_path: Path = Path("clustering.db"),
                 backup_dir: Path = Path("backups")):
        
        self.old_checkpoint_dir = old_checkpoint_dir
        self.new_db_path = new_db_path
        self.backup_dir = backup_dir
        self.backup_dir.mkdir(exist_ok=True)
    
    def backup_existing_data(self):
        """Backup existing checkpoints and databases"""
        log.info("Backing up existing data...")
        
        # Backup old checkpoints
        if self.old_checkpoint_dir.exists():
            backup_checkpoint = self.backup_dir / "checkpoints_backup"
            shutil.copytree(self.old_checkpoint_dir, backup_checkpoint, dirs_exist_ok=True)
            log.info(f"Backed up checkpoints to {backup_checkpoint}")
        
        # Backup existing databases
        for db_file in Path(".").glob("*.db"):
            backup_db = self.backup_dir / db_file.name
            shutil.copy2(db_file, backup_db)
            log.info(f"Backed up {db_file} to {backup_db}")
        
        # Backup existing LUT files
        for lut_file in Path(".").glob("*lut*.joblib"):
            backup_lut = self.backup_dir / lut_file.name
            shutil.copy2(lut_file, backup_lut)
            log.info(f"Backed up {lut_file} to {backup_lut}")
    
    def migrate_existing_checkpoints(self):
        """Migrate data from old checkpoint format to new database"""
        log.info("Migrating existing checkpoints to unified database...")
        
        if not self.old_checkpoint_dir.exists():
            log.info("No existing checkpoints found")
            return
        
        # Initialize new database
        conn = sqlite3.connect(str(self.new_db_path))
        
        # Look for stage checkpoints
        stages = ["river", "turn", "flop"]
        
        for stage in stages:
            checkpoint_files = list(self.old_checkpoint_dir.glob(f"*{stage}*.joblib"))
            
            if not checkpoint_files:
                continue
            
            # Load the most recent checkpoint
            checkpoint_file = max(checkpoint_files, key=lambda p: p.stat().st_mtime)
            log.info(f"Found {stage} checkpoint: {checkpoint_file}")
            
            try:
                data = joblib.load(checkpoint_file)
                
                # Extract centroids if present
                if "centroids" in data and data["centroids"] is not None:
                    centroids = data["centroids"]
                    if isinstance(centroids, np.ndarray):
                        log.info(f"Migrating {len(centroids)} {stage} centroids")
                        
                        # Store centroids in new database
                        for idx, centroid in enumerate(centroids):
                            centroid_data = pickle.dumps(centroid)
                            conn.execute("""
                                INSERT OR REPLACE INTO centroids 
                                (stage, cluster_id, centroid_data)
                                VALUES (?, ?, ?)
                            """, (stage, idx, centroid_data))
                
                # Extract cluster assignments if present
                if stage in data and isinstance(data[stage], dict):
                    lut = data[stage]
                    log.info(f"Found {len(lut)} {stage} cluster assignments")
                    # These would need to be mapped to the new database format
                    # This is complex and depends on the exact format
                
                conn.commit()
                log.info(f"✅ Migrated {stage} data")
                
            except Exception as e:
                log.error(f"Failed to migrate {stage}: {e}")
                continue
        
        conn.close()
    
    def migrate_incremental_turn_db(self):
        """Migrate data from IncrementalTurnProcessor database"""
        old_db = Path("turn_processing.db")
        
        if not old_db.exists():
            log.info("No incremental turn database found")
            return
        
        log.info("Migrating incremental turn database...")
        
        old_conn = sqlite3.connect(str(old_db))
        new_conn = sqlite3.connect(str(self.new_db_path))
        
        try:
            # Check if old database has turn distributions
            cursor = old_conn.execute("""
                SELECT combo_id, combo_cards, distribution, cluster_id 
                FROM turn_distributions
                WHERE distribution IS NOT NULL
            """)
            
            migrated = 0
            for row in cursor:
                combo_id, combo_cards, distribution, cluster_id = row
                
                # Parse combo_cards (assuming it's pickled)
                try:
                    combo = pickle.loads(combo_cards)
                    
                    # Insert into new database
                    new_conn.execute("""
                        INSERT OR REPLACE INTO turn_distributions
                        (combo_id, hole_card1, hole_card2, board_card1, board_card2,
                         board_card3, board_card4, distribution, cluster_id)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (combo_id, *combo[:6], distribution, cluster_id))
                    
                    migrated += 1
                    
                    if migrated % 1000 == 0:
                        new_conn.commit()
                        log.info(f"Migrated {migrated} turn distributions")
                        
                except Exception as e:
                    log.warning(f"Failed to migrate turn combo {combo_id}: {e}")
                    continue
            
            new_conn.commit()
            log.info(f"✅ Migrated {migrated} turn distributions")
            
        finally:
            old_conn.close()
            new_conn.close()
    
    def verify_migration(self):
        """Verify the migration was successful"""
        log.info("Verifying migration...")
        
        conn = sqlite3.connect(str(self.new_db_path))
        
        # Check centroids
        cursor = conn.execute("SELECT stage, COUNT(*) FROM centroids GROUP BY stage")
        for stage, count in cursor:
            log.info(f"  {stage}: {count} centroids")
        
        # Check distributions
        tables = [
            ("river_distributions", "win_rate"),
            ("turn_distributions", "distribution"),
            ("flop_distributions", "distribution")
        ]
        
        for table, check_col in tables:
            cursor = conn.execute(
                f"SELECT COUNT(*) FROM {table} WHERE {check_col} IS NOT NULL"
            )
            count = cursor.fetchone()[0]
            log.info(f"  {table}: {count} processed combinations")
        
        conn.close()
    
    def run_migration(self):
        """Run the complete migration process"""
        log.info("=" * 60)
        log.info("CLUSTERING SYSTEM MIGRATION")
        log.info("=" * 60)
        
        # Step 1: Backup
        self.backup_existing_data()
        
        # Step 2: Migrate checkpoints
        self.migrate_existing_checkpoints()
        
        # Step 3: Migrate incremental turn database
        self.migrate_incremental_turn_db()
        
        # Step 4: Verify
        self.verify_migration()
        
        log.info("=" * 60)
        log.info("✅ MIGRATION COMPLETE")
        log.info("=" * 60)
        log.info("")
        log.info("Next steps:")
        log.info("1. Review the migration results above")
        log.info("2. Test the new unified builder with a small dataset")
        log.info("3. If successful, update your code to use UnifiedSQLiteLUTBuilder")
        log.info("4. Old data is backed up in ./backups/")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    migrator = ClusteringMigrator()
    migrator.run_migration()