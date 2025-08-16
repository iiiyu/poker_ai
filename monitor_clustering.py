#!/usr/bin/env python3
"""
Monitor clustering progress with time estimates.
Run this alongside 'make run-cluster' to see detailed progress.
"""

import time
import psutil
from datetime import datetime, timedelta

def monitor_clustering():
    """Monitor clustering progress with detailed estimates."""
    print("="*60)
    print("CLUSTERING PROGRESS MONITOR")
    print("="*60)
    print("\nMonitoring clustering process...")
    print("Press Ctrl+C to stop monitoring (clustering will continue)\n")
    
    start_time = datetime.now()
    
    # Expected times (rough estimates)
    stages = {
        "River": {"combos": 2598960, "time_per_1000": 2},    # ~2s per 1000
        "Turn": {"combos": 305377, "time_per_1000": 10},     # ~10s per 1000
        "Flop": {"combos": 155040, "time_per_1000": 60},     # ~60s per 1000
    }
    
    try:
        while True:
            current_time = datetime.now()
            elapsed = current_time - start_time
            
            print(f"\n{'='*60}")
            print(f"Elapsed Time: {str(elapsed).split('.')[0]}")
            print(f"Current Time: {current_time.strftime('%H:%M:%S')}")
            print("="*60)
            
            # Check if clustering process is running
            clustering_running = any('poker_ai' in ' '.join(p.cmdline()) and 'cluster' in ' '.join(p.cmdline())
                                    for p in psutil.process_iter(['cmdline']) 
                                    if p.info['cmdline'])
            
            if clustering_running:
                print("✅ Clustering process is running")
                
                # System resources
                cpu_percent = psutil.cpu_percent(interval=1)
                memory = psutil.virtual_memory()
                print(f"\n💻 System Resources:")
                print(f"   CPU Usage: {cpu_percent:.1f}%")
                print(f"   Memory: {memory.percent:.1f}% ({memory.used / (1024**3):.1f}GB used)")
                
                print("\n📊 Stage Estimates:")
                for stage, info in stages.items():
                    total_time = info["combos"] * info["time_per_1000"] / 1000
                    print(f"\n   {stage}:")
                    print(f"   - Combinations: {info['combos']:,}")
                    print(f"   - Estimated time: {total_time/60:.1f} minutes")
                    print(f"   - Speed: ~{1000/info['time_per_1000']:.0f} combos/second")
                
                total_est = sum(s["combos"] * s["time_per_1000"] / 1000 for s in stages.values())
                print(f"\n📈 Total Estimated Time: {total_est/60:.1f} minutes")
                
                print("\n💡 Tips:")
                print("- Flop clustering is the slowest (many simulations)")
                print("- Progress will appear frozen at 0% initially")
                print("- First progress update may take 1-2 minutes")
                print("- The process WILL complete, be patient!")
                
            else:
                print("⚠️  Clustering process not detected")
                print("\nStart clustering with: make run-cluster")
            
            time.sleep(10)
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped. Clustering continues in background.")

if __name__ == "__main__":
    monitor_clustering()