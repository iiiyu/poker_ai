#!/usr/bin/env python3
"""
Long-running AI training script with automatic LUT generation and resume capability.
"""

import os
import sys
import time
import subprocess
import argparse
import logging
from pathlib import Path
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f'training_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')
    ]
)
logger = logging.getLogger(__name__)

def check_lut_exists():
    """Check if card_info_lut.joblib exists."""
    lut_path = Path('card_info_lut.joblib')
    return lut_path.exists()

def generate_lut():
    """Generate card info lookup tables."""
    logger.info("Card info LUT not found. Generating lookup tables...")
    logger.info("This is a one-time process and may take 15-30 minutes...")
    
    try:
        # Use uv run to ensure proper environment
        result = subprocess.run(
            ['uv', 'run', 'poker_ai', 'cluster'],
            capture_output=True,
            text=True,
            check=True
        )
        logger.info("LUT generation completed successfully!")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to generate LUT: {e}")
        logger.error(f"Output: {e.stdout}")
        logger.error(f"Error: {e.stderr}")
        return False
    except FileNotFoundError:
        logger.error("uv command not found. Please ensure uv is installed.")
        return False

def find_latest_strategy():
    """Find the most recent strategy file for resuming."""
    strategy_files = list(Path('.').glob('**/offline_strategy_*.gz'))
    if not strategy_files:
        return None
    
    # Sort by modification time and get the most recent
    strategy_files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return str(strategy_files[0])

def train_new_agent(args):
    """Start training a new agent."""
    logger.info("Starting new agent training...")
    logger.info(f"Configuration:")
    logger.info(f"  - Iterations: {args.iterations}")
    logger.info(f"  - Players: {args.players}")
    logger.info(f"  - Save interval: {args.save_interval}")
    
    cmd = [
        'uv', 'run', 'poker_ai', 'train', 'start',
        '--n_iterations', str(args.iterations),
        '--n_players', str(args.players),
        '--dump_iteration', str(args.save_interval)
    ]
    
    if not args.single_process:
        cmd.append('--multi_process')
    
    logger.info(f"Running command: {' '.join(cmd)}")
    
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        # Stream output in real-time
        for line in iter(process.stdout.readline, ''):
            if line:
                print(line.rstrip())
                sys.stdout.flush()
        
        process.wait()
        return process.returncode == 0
        
    except KeyboardInterrupt:
        logger.info("\nTraining interrupted by user. You can resume later.")
        process.terminate()
        process.wait()
        return False
    except Exception as e:
        logger.error(f"Training failed: {e}")
        return False

def resume_training(strategy_path, args):
    """Resume training from an existing strategy."""
    logger.info(f"Resuming training from: {strategy_path}")
    logger.info(f"Note: Resume command will continue with original settings")
    
    # For resume, we need to find the server config file
    strategy_dir = Path(strategy_path).parent
    server_files = list(strategy_dir.glob('server*.gz'))
    
    if not server_files:
        logger.error(f"No server config file found in {strategy_dir}")
        logger.info("Starting new training instead...")
        return train_new_agent(args)
    
    server_config = server_files[0]  # Use the first/only server file
    
    cmd = [
        'uv', 'run', 'poker_ai', 'train', 'resume',
        '--server_config_path', str(server_config)
    ]
    
    logger.info(f"Running command: {' '.join(cmd)}")
    
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        # Stream output in real-time
        for line in iter(process.stdout.readline, ''):
            if line:
                print(line.rstrip())
                sys.stdout.flush()
        
        process.wait()
        return process.returncode == 0
        
    except KeyboardInterrupt:
        logger.info("\nTraining interrupted by user. You can resume later.")
        process.terminate()
        process.wait()
        return False
    except Exception as e:
        logger.error(f"Training failed: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Long-running poker AI training with automatic setup'
    )
    parser.add_argument(
        '--iterations',
        type=int,
        default=1000000,
        help='Number of training iterations (default: 1,000,000)'
    )
    parser.add_argument(
        '--players',
        type=int,
        default=3,
        help='Number of players (2-6, default: 3)'
    )
    parser.add_argument(
        '--save_interval',
        type=int,
        default=10000,
        help='Save strategy every N iterations (default: 10,000)'
    )
    parser.add_argument(
        '--single_process',
        action='store_true',
        help='Use single process instead of multiprocessing'
    )
    parser.add_argument(
        '--resume',
        action='store_true',
        help='Resume from most recent strategy file'
    )
    parser.add_argument(
        '--strategy_path',
        type=str,
        help='Specific strategy file to resume from'
    )
    parser.add_argument(
        '--loop',
        action='store_true',
        help='Continuously train in a loop (for very long training)'
    )
    parser.add_argument(
        '--loop_iterations',
        type=int,
        default=100000,
        help='Iterations per loop cycle (default: 100,000)'
    )
    
    args = parser.parse_args()
    
    # Step 1: Check and generate LUT if needed
    if not check_lut_exists():
        logger.info("=" * 60)
        logger.info("SETUP: Card Info Lookup Tables")
        logger.info("=" * 60)
        
        if not generate_lut():
            logger.error("Failed to generate LUT. Cannot proceed with training.")
            sys.exit(1)
        
        logger.info("LUT generation complete!")
        logger.info("=" * 60)
        time.sleep(2)
    else:
        logger.info("Card info LUT found: card_info_lut.joblib ✓")
    
    # Step 2: Determine training mode
    logger.info("=" * 60)
    logger.info("POKER AI TRAINING")
    logger.info("=" * 60)
    
    if args.resume or args.strategy_path:
        # Resume mode
        if args.strategy_path:
            strategy_path = args.strategy_path
            if not Path(strategy_path).exists():
                logger.error(f"Strategy file not found: {strategy_path}")
                sys.exit(1)
        else:
            strategy_path = find_latest_strategy()
            if not strategy_path:
                logger.error("No existing strategy found to resume from.")
                logger.info("Starting new training instead...")
                args.resume = False
            else:
                logger.info(f"Found latest strategy: {strategy_path}")
    
    # Step 3: Run training
    if args.loop:
        # Continuous training loop
        logger.info("Starting continuous training loop...")
        logger.info(f"Each cycle: {args.loop_iterations} iterations")
        logger.info("Press Ctrl+C to stop at any time")
        
        cycle = 0
        while True:
            cycle += 1
            logger.info(f"\n{'='*60}")
            logger.info(f"TRAINING CYCLE {cycle}")
            logger.info(f"{'='*60}")
            
            if cycle == 1 and not (args.resume or args.strategy_path):
                # First cycle, new training
                success = train_new_agent(args)
            else:
                # Resume from latest
                strategy_path = find_latest_strategy()
                if strategy_path:
                    args.iterations = args.loop_iterations
                    success = resume_training(strategy_path, args)
                else:
                    logger.error("No strategy found to resume from!")
                    break
            
            if not success:
                logger.info("Training stopped.")
                break
            
            logger.info(f"Cycle {cycle} complete. Starting next cycle in 5 seconds...")
            time.sleep(5)
    
    else:
        # Single training session
        if args.resume or args.strategy_path:
            success = resume_training(strategy_path, args)
        else:
            success = train_new_agent(args)
        
        if success:
            logger.info("=" * 60)
            logger.info("Training completed successfully!")
            
            # Find and display the latest strategy
            latest_strategy = find_latest_strategy()
            if latest_strategy:
                logger.info(f"Strategy saved to: {latest_strategy}")
                logger.info("\nNext steps:")
                logger.info(f"1. Test against Slumbot:")
                logger.info(f"   uv run test_slumbot.py --strategy_path {latest_strategy}")
                logger.info(f"2. Play against the AI:")
                logger.info(f"   uv run poker_ai play --agent offline --strategy_path {latest_strategy}")
                logger.info(f"3. Continue training:")
                logger.info(f"   python train_long_ai.py --resume --iterations 1000000")
        else:
            logger.info("Training was interrupted or failed.")
            latest_strategy = find_latest_strategy()
            if latest_strategy:
                logger.info(f"You can resume from: {latest_strategy}")
                logger.info(f"Run: python train_long_ai.py --resume")

if __name__ == '__main__':
    main()