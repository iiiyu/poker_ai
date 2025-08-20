"""
Training interface for the Zig poker AI.

Provides both synchronous and asynchronous training interfaces,
progress monitoring, checkpointing, and compatibility with existing
Python training workflows.
"""

import asyncio
import threading
import time
from typing import Dict, Any, Optional, Callable, List, Union
from dataclasses import dataclass, field
from pathlib import Path
import logging
from concurrent.futures import ThreadPoolExecutor, Future
import signal
import os

from .poker_ai_zig import CFRTrainer, get_zig_library, PokerAIError
from .strategy_loader import get_strategy_loader, StrategyFormat

logger = logging.getLogger(__name__)

@dataclass
class TrainingConfig:
    """Configuration for CFR training."""
    iterations: int = 1000
    num_threads: int = 1
    checkpoint_interval: int = 100
    save_interval: int = 200
    strategy_save_path: str = "strategy.zig"
    checkpoint_save_path: str = "checkpoint.zig"
    log_interval: int = 10
    enable_logging: bool = True
    max_memory_mb: int = 4096
    
    # CFR-specific parameters
    exploration_probability: float = 0.6
    prune_threshold: float = -300.0
    discount_alpha: float = 1.5
    discount_beta: float = 0.0

@dataclass
class TrainingProgress:
    """Training progress information."""
    current_iteration: int = 0
    total_iterations: int = 0
    elapsed_time: float = 0.0
    iterations_per_second: float = 0.0
    estimated_time_remaining: float = 0.0
    memory_usage_mb: float = 0.0
    last_checkpoint: int = 0
    last_save: int = 0
    is_running: bool = False
    error_message: Optional[str] = None

class TrainingMonitor:
    """Monitors training progress and handles callbacks."""
    
    def __init__(self, config: TrainingConfig):
        self.config = config
        self.progress = TrainingProgress(total_iterations=config.iterations)
        self.callbacks: List[Callable[[TrainingProgress], None]] = []
        self.start_time = 0.0
        self._stop_requested = False
    
    def add_callback(self, callback: Callable[[TrainingProgress], None]) -> None:
        """Add a progress callback function."""
        self.callbacks.append(callback)
    
    def start(self) -> None:
        """Start monitoring."""
        self.start_time = time.time()
        self.progress.is_running = True
        self._stop_requested = False
    
    def update(self, iteration: int) -> None:
        """Update progress."""
        self.progress.current_iteration = iteration
        self.progress.elapsed_time = time.time() - self.start_time
        
        if self.progress.elapsed_time > 0:
            self.progress.iterations_per_second = iteration / self.progress.elapsed_time
            remaining_iterations = self.progress.total_iterations - iteration
            if self.progress.iterations_per_second > 0:
                self.progress.estimated_time_remaining = (
                    remaining_iterations / self.progress.iterations_per_second
                )
        
        # Update memory usage (placeholder - would need Zig API)
        self.progress.memory_usage_mb = 0.0
        
        # Trigger callbacks
        for callback in self.callbacks:
            try:
                callback(self.progress)
            except Exception as e:
                logger.warning(f"Progress callback failed: {e}")
    
    def stop(self, error_message: Optional[str] = None) -> None:
        """Stop monitoring."""
        self.progress.is_running = False
        self.progress.error_message = error_message
        self._stop_requested = True
    
    def should_stop(self) -> bool:
        """Check if training should stop."""
        return self._stop_requested

class ZigTrainingInterface:
    """High-level interface for Zig poker AI training."""
    
    def __init__(self, config: TrainingConfig):
        self.config = config
        self.monitor = TrainingMonitor(config)
        self.trainer: Optional[CFRTrainer] = None
        self.strategy_loader = get_strategy_loader()
        self._training_thread: Optional[threading.Thread] = None
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._setup_signal_handlers()
    
    def _setup_signal_handlers(self) -> None:
        """Setup signal handlers for graceful shutdown."""
        def signal_handler(signum, frame):
            logger.info(f"Received signal {signum}, stopping training...")
            self.stop_training()
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    def create_trainer(self) -> CFRTrainer:
        """Create a new CFR trainer with current config."""
        if self.trainer is not None:
            del self.trainer
        
        self.trainer = CFRTrainer(
            iterations=self.config.iterations,
            num_threads=self.config.num_threads
        )
        
        return self.trainer
    
    def load_checkpoint(self, checkpoint_path: str) -> None:
        """Load training checkpoint."""
        if not os.path.exists(checkpoint_path):
            raise FileNotFoundError(f"Checkpoint not found: {checkpoint_path}")
        
        if self.trainer is None:
            self.create_trainer()
        
        self.trainer.load_strategy(checkpoint_path)
        logger.info(f"Loaded checkpoint from {checkpoint_path}")
    
    def save_checkpoint(self, checkpoint_path: Optional[str] = None) -> None:
        """Save training checkpoint."""
        if self.trainer is None:
            raise RuntimeError("No trainer available for checkpoint")
        
        path = checkpoint_path or self.config.checkpoint_save_path
        self.trainer.save_strategy(path)
        logger.info(f"Saved checkpoint to {path}")
    
    def save_strategy(self, strategy_path: Optional[str] = None) -> None:
        """Save final strategy."""
        if self.trainer is None:
            raise RuntimeError("No trainer available for saving strategy")
        
        path = strategy_path or self.config.strategy_save_path
        self.trainer.save_strategy(path)
        logger.info(f"Saved strategy to {path}")
    
    def train_sync(self, progress_callback: Optional[Callable[[TrainingProgress], None]] = None) -> TrainingProgress:
        """Run training synchronously."""
        if progress_callback:
            self.monitor.add_callback(progress_callback)
        
        if self.trainer is None:
            self.create_trainer()
        
        self.monitor.start()
        
        try:
            # Start training in Zig
            # Note: The actual Zig implementation would need to support
            # iteration-by-iteration training with progress callbacks
            self._run_training_with_progress()
            
            # Save final strategy
            self.save_strategy()
            
        except Exception as e:
            logger.error(f"Training failed: {e}")
            self.monitor.stop(str(e))
            raise
        
        self.monitor.stop()
        return self.monitor.progress
    
    async def train_async(self, progress_callback: Optional[Callable[[TrainingProgress], None]] = None) -> TrainingProgress:
        """Run training asynchronously."""
        loop = asyncio.get_event_loop()
        
        # Run training in executor to avoid blocking
        future = self._executor.submit(self.train_sync, progress_callback)
        
        # Wait for completion while allowing other coroutines to run
        while not future.done():
            await asyncio.sleep(0.1)
        
        return future.result()
    
    def stop_training(self) -> None:
        """Request training to stop gracefully."""
        self.monitor.stop()
        logger.info("Training stop requested")
    
    def _run_training_with_progress(self) -> None:
        """Run training with progress monitoring."""
        # This is a simplified implementation
        # In reality, the Zig trainer would need to support callbacks
        # or we'd need to poll its progress
        
        for iteration in range(1, self.config.iterations + 1):
            # Check for stop request
            if self.monitor.should_stop():
                logger.info(f"Training stopped at iteration {iteration}")
                break
            
            # Simulate training step (in real implementation, this would be Zig)
            time.sleep(0.001)  # Simulate work
            
            # Update progress
            self.monitor.update(iteration)
            
            # Handle checkpointing
            if iteration % self.config.checkpoint_interval == 0:
                self.save_checkpoint()
                self.monitor.progress.last_checkpoint = iteration
            
            # Handle strategy saving
            if iteration % self.config.save_interval == 0:
                self.save_strategy()
                self.monitor.progress.last_save = iteration
            
            # Log progress
            if self.config.enable_logging and iteration % self.config.log_interval == 0:
                self._log_progress(iteration)
        
        # Final training call to Zig
        if self.trainer and not self.monitor.should_stop():
            try:
                self.trainer.train()
            except PokerAIError as e:
                raise RuntimeError(f"Zig training failed: {e}")
    
    def _log_progress(self, iteration: int) -> None:
        """Log training progress."""
        progress = self.monitor.progress
        logger.info(
            f"Iteration {iteration}/{progress.total_iterations} "
            f"({progress.iterations_per_second:.1f} it/s, "
            f"ETA: {progress.estimated_time_remaining:.1f}s)"
        )

class BatchTrainingManager:
    """Manages batch training jobs with multiple configurations."""
    
    def __init__(self):
        self.jobs: List[TrainingJob] = []
        self.active_jobs: Dict[str, ZigTrainingInterface] = {}
    
    def add_job(self, job_id: str, config: TrainingConfig) -> None:
        """Add a training job to the batch."""
        job = TrainingJob(job_id, config)
        self.jobs.append(job)
    
    def run_batch_sync(self, max_concurrent: int = 1) -> Dict[str, TrainingProgress]:
        """Run all jobs synchronously with limited concurrency."""
        results = {}
        
        with ThreadPoolExecutor(max_workers=max_concurrent) as executor:
            # Submit all jobs
            futures = {}
            for job in self.jobs:
                interface = ZigTrainingInterface(job.config)
                future = executor.submit(interface.train_sync)
                futures[job.job_id] = future
                self.active_jobs[job.job_id] = interface
            
            # Collect results
            for job_id, future in futures.items():
                try:
                    results[job_id] = future.result()
                except Exception as e:
                    logger.error(f"Job {job_id} failed: {e}")
                    results[job_id] = TrainingProgress(error_message=str(e))
                finally:
                    # Cleanup
                    if job_id in self.active_jobs:
                        del self.active_jobs[job_id]
        
        return results
    
    async def run_batch_async(self, max_concurrent: int = 1) -> Dict[str, TrainingProgress]:
        """Run all jobs asynchronously with limited concurrency."""
        semaphore = asyncio.Semaphore(max_concurrent)
        
        async def run_job(job):
            async with semaphore:
                interface = ZigTrainingInterface(job.config)
                self.active_jobs[job.job_id] = interface
                try:
                    return await interface.train_async()
                finally:
                    if job.job_id in self.active_jobs:
                        del self.active_jobs[job.job_id]
        
        # Run all jobs
        tasks = [run_job(job) for job in self.jobs]
        results_list = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Create results dict
        results = {}
        for job, result in zip(self.jobs, results_list):
            if isinstance(result, Exception):
                logger.error(f"Job {job.job_id} failed: {result}")
                results[job.job_id] = TrainingProgress(error_message=str(result))
            else:
                results[job.job_id] = result
        
        return results
    
    def stop_all_jobs(self) -> None:
        """Stop all active training jobs."""
        for interface in self.active_jobs.values():
            interface.stop_training()

@dataclass
class TrainingJob:
    """Represents a single training job."""
    job_id: str
    config: TrainingConfig
    created_at: float = field(default_factory=time.time)

class CompatibilityTrainer:
    """Training interface that maintains compatibility with existing Python code."""
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize with Python-style config dict."""
        # Convert Python config to TrainingConfig
        self.training_config = TrainingConfig(
            iterations=config.get('iterations', 1000),
            num_threads=config.get('n_jobs', 1),
            checkpoint_interval=config.get('checkpoint_every', 100),
            save_interval=config.get('save_every', 200),
            strategy_save_path=config.get('save_path', 'strategy.zig'),
            enable_logging=config.get('verbose', True),
        )
        
        self.interface = ZigTrainingInterface(self.training_config)
    
    def train(self, show_progress: bool = True) -> Dict[str, Any]:
        """Train with Python-compatible interface."""
        def progress_callback(progress: TrainingProgress):
            if show_progress:
                print(f"\rIteration {progress.current_iteration}/{progress.total_iterations} "
                      f"({progress.iterations_per_second:.1f} it/s)", end='', flush=True)
        
        result = self.interface.train_sync(progress_callback if show_progress else None)
        
        if show_progress:
            print()  # New line after progress
        
        # Return Python-compatible result
        return {
            'iterations_completed': result.current_iteration,
            'total_time': result.elapsed_time,
            'iterations_per_second': result.iterations_per_second,
            'memory_usage_mb': result.memory_usage_mb,
            'success': result.error_message is None,
            'error': result.error_message,
        }
    
    def save(self, path: str, format: str = StrategyFormat.JOBLIB) -> None:
        """Save strategy in Python format."""
        # Save in Zig format first
        zig_path = path + '.zig_temp'
        self.interface.save_strategy(zig_path)
        
        try:
            # Convert to Python format
            self.interface.strategy_loader.convert_zig_to_python(
                zig_path, path, format
            )
        finally:
            # Cleanup temp file
            if os.path.exists(zig_path):
                os.unlink(zig_path)
    
    def load(self, path: str) -> None:
        """Load strategy from Python format."""
        format = self.interface.strategy_loader.detect_format(path)
        
        if format == StrategyFormat.ZIG_BINARY:
            # Load directly
            self.interface.load_checkpoint(path)
        else:
            # Convert from Python format
            zig_path = path + '.zig_temp'
            try:
                python_strategy = self.interface.strategy_loader.load_python_strategy(path, format)
                self.interface.strategy_loader.convert_python_to_zig(python_strategy, zig_path)
                self.interface.load_checkpoint(zig_path)
            finally:
                if os.path.exists(zig_path):
                    os.unlink(zig_path)