#!/usr/bin/env python3
"""
Check LUT generation progress and manage checkpoints.
"""

import os
import sys
from pathlib import Path
import joblib
from datetime import datetime
import shutil

def format_size(bytes):
    """Format bytes to human readable size."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes < 1024.0:
            return f"{bytes:.2f} {unit}"
        bytes /= 1024.0
    return f"{bytes:.2f} TB"

def check_lut_progress():
    """Check the progress of LUT generation."""
    print("="*60)
    print("LUT GENERATION PROGRESS CHECK")
    print("="*60)
    print()
    
    # Check main files
    main_lut = Path("card_info_lut.joblib")
    centroids = Path("centroids.joblib")
    
    if not main_lut.exists():
        print("❌ No LUT file found (card_info_lut.joblib)")
        print("\nTo start generation, run:")
        print("  ./generate_texas_holdem_lut_safe.sh standard")
        return None
    
    # Load and analyze LUT
    try:
        print(f"📁 Found LUT file: {main_lut}")
        print(f"   Size: {format_size(main_lut.stat().st_size)}")
        print(f"   Modified: {datetime.fromtimestamp(main_lut.stat().st_mtime)}")
        print()
        
        lut = joblib.load(main_lut)
        
        if not isinstance(lut, dict):
            print("❌ LUT file is corrupted (not a dictionary)")
            return None
            
        print("📊 Completed Stages:")
        stages = ["pre_flop", "river", "turn", "flop"]
        completed = []
        
        for stage in stages:
            if stage in lut:
                if isinstance(lut[stage], dict):
                    entries = len(lut[stage])
                    completed.append(stage)
                    print(f"   ✅ {stage:10s}: {entries:,} entries")
                else:
                    print(f"   ⚠️  {stage:10s}: Present but invalid format")
            else:
                print(f"   ❌ {stage:10s}: Not completed")
        
        # Calculate completion percentage
        completion = len(completed) / len(stages) * 100
        print(f"\n📈 Overall Progress: {completion:.0f}%")
        
        if completion == 100:
            print("🎉 All stages completed!")
            print("\nYou can now use this LUT for training:")
            print("  ./train_ai.sh medium")
        else:
            print(f"\n⏳ Incomplete stages: {[s for s in stages if s not in completed]}")
            print("\nTo resume generation, run:")
            print("  ./generate_texas_holdem_lut_safe.sh standard resume")
        
        # Check for checkpoint files
        print("\n📦 Checkpoint Files:")
        checkpoints = list(Path(".").glob("checkpoint_*.joblib"))
        if checkpoints:
            for cp in checkpoints:
                print(f"   - {cp.name} ({format_size(cp.stat().st_size)})")
        else:
            print("   No checkpoint files found")
        
        # Check centroids file
        if centroids.exists():
            print(f"\n🎯 Centroids file: {centroids}")
            print(f"   Size: {format_size(centroids.stat().st_size)}")
        
        return lut
        
    except Exception as e:
        print(f"❌ Error loading LUT: {e}")
        print("\nThe file may be corrupted. Options:")
        print("1. Try to resume: ./generate_texas_holdem_lut_safe.sh standard resume")
        print("2. Start fresh: Delete card_info_lut.joblib and run generation again")
        return None

def recover_from_checkpoint():
    """Try to recover from checkpoint files."""
    print("\n" + "="*60)
    print("CHECKPOINT RECOVERY")
    print("="*60)
    
    checkpoints = list(Path(".").glob("checkpoint_*.joblib"))
    
    if not checkpoints:
        print("No checkpoint files found.")
        return False
    
    print(f"Found {len(checkpoints)} checkpoint file(s):")
    
    # Sort by modification time
    checkpoints.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    
    for i, cp in enumerate(checkpoints):
        print(f"\n{i+1}. {cp.name}")
        print(f"   Size: {format_size(cp.stat().st_size)}")
        print(f"   Modified: {datetime.fromtimestamp(cp.stat().st_mtime)}")
        
        try:
            lut = joblib.load(cp)
            if isinstance(lut, dict):
                stages = list(lut.keys())
                print(f"   Stages: {stages}")
            else:
                print("   ⚠️  Invalid format")
        except:
            print("   ❌ Cannot load")
    
    # Ask user which to recover
    print("\nOptions:")
    print("1. Recover from most recent checkpoint")
    print("2. Choose specific checkpoint")
    print("3. Cancel")
    
    choice = input("\nEnter choice (1-3): ").strip()
    
    if choice == "1" and checkpoints:
        checkpoint = checkpoints[0]
        print(f"\nRecovering from {checkpoint.name}...")
        
        # Backup current files
        if Path("card_info_lut.joblib").exists():
            backup_name = f"card_info_lut_{datetime.now().strftime('%Y%m%d_%H%M%S')}.bak"
            shutil.copy("card_info_lut.joblib", backup_name)
            print(f"Backed up current LUT to {backup_name}")
        
        # Copy checkpoint to main file
        shutil.copy(checkpoint, "card_info_lut.joblib")
        print("✅ Recovery complete!")
        print("\nRun progress check again to verify:")
        print("  python check_lut_progress.py")
        return True
    
    return False

def estimate_remaining_time(lut):
    """Estimate remaining time based on completed stages."""
    if not lut or not isinstance(lut, dict):
        return
    
    print("\n" + "="*60)
    print("TIME ESTIMATION")
    print("="*60)
    
    stages = {
        "pre_flop": {"time": 0.1, "name": "Preflop"},  # Very fast
        "river": {"time": 10, "name": "River"},        # 10 minutes
        "turn": {"time": 30, "name": "Turn"},          # 30 minutes
        "flop": {"time": 150, "name": "Flop"},         # 2.5 hours
    }
    
    total_time = sum(s["time"] for s in stages.values())
    completed_time = sum(stages[s]["time"] for s in lut.keys() if s in stages)
    remaining_time = total_time - completed_time
    
    print(f"Estimated times (standard mode):")
    for stage, info in stages.items():
        if stage in lut:
            print(f"  ✅ {info['name']:10s}: Completed")
        else:
            print(f"  ⏳ {info['name']:10s}: ~{info['time']:.1f} minutes")
    
    print(f"\nTotal remaining time: ~{remaining_time:.0f} minutes ({remaining_time/60:.1f} hours)")
    
    if remaining_time > 0:
        print("\nTips to speed up:")
        print("  • Use 'test' mode for faster (lower quality) generation")
        print("  • Ensure no other heavy processes are running")
        print("  • Consider implementing in Rust (20-40x faster!)")

def main():
    """Main function."""
    if len(sys.argv) > 1 and sys.argv[1] == "recover":
        recover_from_checkpoint()
    else:
        lut = check_lut_progress()
        if lut:
            estimate_remaining_time(lut)
        
        print("\n" + "="*60)
        print("OPTIONS")
        print("="*60)
        print("• Check progress:  python check_lut_progress.py")
        print("• Recover from checkpoint:  python check_lut_progress.py recover")
        print("• Resume generation:  ./generate_texas_holdem_lut_safe.sh standard resume")
        print("• Monitor while running:  python monitor_clustering.py")

if __name__ == "__main__":
    main()