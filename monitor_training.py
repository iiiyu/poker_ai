#!/usr/bin/env python3
"""
Monitor training progress and display statistics.
"""

import os
import sys
import time
import glob
from pathlib import Path
from datetime import datetime, timedelta
import gzip
import pickle

def format_number(n):
    """Format large numbers with K/M/B suffixes."""
    if n < 1000:
        return str(n)
    elif n < 1000000:
        return f"{n/1000:.1f}K"
    elif n < 1000000000:
        return f"{n/1000000:.1f}M"
    else:
        return f"{n/1000000000:.1f}B"

def get_file_size_mb(filepath):
    """Get file size in MB."""
    return os.path.getsize(filepath) / (1024 * 1024)

def estimate_iterations_from_size(size_mb):
    """Estimate iterations based on file size (rough estimate)."""
    # Rough estimate: ~0.1 MB per 1000 iterations
    return int(size_mb * 10000)

def find_training_directories():
    """Find all training directories."""
    dirs = []
    for path in Path('.').glob('**/'):
        if path.is_dir() and any(path.glob('offline_strategy*.gz')):
            dirs.append(path)
    return sorted(dirs, key=lambda x: x.stat().st_mtime, reverse=True)

def get_training_info(directory):
    """Get information about a training run."""
    info = {
        'path': directory,
        'strategies': [],
        'latest_strategy': None,
        'start_time': None,
        'latest_time': None,
        'estimated_iterations': 0
    }
    
    # Find all strategy files
    strategy_files = sorted(directory.glob('offline_strategy*.gz'))
    
    if strategy_files:
        info['strategies'] = strategy_files
        info['latest_strategy'] = strategy_files[-1]
        info['start_time'] = datetime.fromtimestamp(strategy_files[0].stat().st_mtime)
        info['latest_time'] = datetime.fromtimestamp(strategy_files[-1].stat().st_mtime)
        
        # Estimate iterations from latest file size
        size_mb = get_file_size_mb(info['latest_strategy'])
        info['estimated_iterations'] = estimate_iterations_from_size(size_mb)
        info['size_mb'] = size_mb
    
    return info

def monitor_latest_training():
    """Monitor the most recent training run."""
    print("=" * 70)
    print("POKER AI TRAINING MONITOR")
    print("=" * 70)
    print()
    
    while True:
        try:
            # Clear screen (works on Unix/Linux/Mac)
            os.system('clear' if os.name == 'posix' else 'cls')
            
            print("=" * 70)
            print(f"POKER AI TRAINING MONITOR - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print("=" * 70)
            print()
            
            # Find training directories
            training_dirs = find_training_directories()
            
            if not training_dirs:
                print("No training runs found.")
                print("Start training with: ./train_ai.sh")
                time.sleep(5)
                continue
            
            # Get info for latest training
            latest_dir = training_dirs[0]
            info = get_training_info(latest_dir)
            
            if info['latest_strategy']:
                print(f"Latest Training: {latest_dir}")
                print(f"Started: {info['start_time'].strftime('%Y-%m-%d %H:%M:%S')}")
                
                # Calculate duration
                duration = info['latest_time'] - info['start_time']
                hours = duration.total_seconds() / 3600
                print(f"Duration: {hours:.1f} hours")
                
                print()
                print("Progress:")
                print(f"  Strategy files: {len(info['strategies'])}")
                print(f"  Latest file: {info['latest_strategy'].name}")
                print(f"  File size: {info['size_mb']:.1f} MB")
                print(f"  Estimated iterations: ~{format_number(info['estimated_iterations'])}")
                
                # Check if still training (file modified recently)
                time_since_update = datetime.now() - info['latest_time']
                if time_since_update < timedelta(minutes=5):
                    print(f"  Status: 🟢 ACTIVE (updated {int(time_since_update.total_seconds())}s ago)")
                elif time_since_update < timedelta(hours=1):
                    print(f"  Status: 🟡 IDLE (updated {int(time_since_update.total_seconds()/60)}m ago)")
                else:
                    print(f"  Status: 🔴 STOPPED (updated {hours:.1f}h ago)")
                
                # Performance metrics
                if hours > 0:
                    iterations_per_hour = info['estimated_iterations'] / hours
                    print()
                    print("Performance:")
                    print(f"  Speed: ~{format_number(int(iterations_per_hour))}/hour")
                    print(f"  Average: ~{format_number(int(iterations_per_hour/3600))}/second")
            
            # Show all training runs
            if len(training_dirs) > 1:
                print()
                print("Other training runs:")
                for dir in training_dirs[1:6]:  # Show up to 5 more
                    other_info = get_training_info(dir)
                    if other_info['latest_strategy']:
                        print(f"  - {dir}: ~{format_number(other_info['estimated_iterations'])} iterations")
            
            print()
            print("Press Ctrl+C to exit monitoring")
            print("Refreshing every 10 seconds...")
            
            time.sleep(10)
            
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(5)

def show_summary():
    """Show summary of all training runs."""
    print("=" * 70)
    print("TRAINING SUMMARY")
    print("=" * 70)
    print()
    
    training_dirs = find_training_directories()
    
    if not training_dirs:
        print("No training runs found.")
        return
    
    total_iterations = 0
    
    for dir in training_dirs:
        info = get_training_info(dir)
        if info['latest_strategy']:
            print(f"Directory: {dir}")
            print(f"  Started: {info['start_time'].strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"  Iterations: ~{format_number(info['estimated_iterations'])}")
            print(f"  Strategy files: {len(info['strategies'])}")
            print(f"  Latest: {info['latest_strategy'].name}")
            print(f"  Size: {info['size_mb']:.1f} MB")
            print()
            
            total_iterations += info['estimated_iterations']
    
    print("-" * 70)
    print(f"Total estimated iterations across all runs: ~{format_number(total_iterations)}")
    
    # Find best (largest) strategy
    all_strategies = []
    for dir in training_dirs:
        all_strategies.extend(dir.glob('offline_strategy*.gz'))
    
    if all_strategies:
        largest = max(all_strategies, key=lambda x: x.stat().st_size)
        print(f"Largest strategy file: {largest}")
        print(f"  Size: {get_file_size_mb(largest):.1f} MB")
        print(f"  Estimated iterations: ~{format_number(estimate_iterations_from_size(get_file_size_mb(largest)))}")

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Monitor poker AI training progress')
    parser.add_argument(
        '--summary',
        action='store_true',
        help='Show summary of all training runs and exit'
    )
    
    args = parser.parse_args()
    
    if args.summary:
        show_summary()
    else:
        monitor_latest_training()