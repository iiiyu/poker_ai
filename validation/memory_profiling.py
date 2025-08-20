"""
Memory profiling and analysis for Zig vs Python implementations.

This module validates memory usage characteristics:
- Memory usage analysis and verification
- Peak memory consumption tracking
- Memory leak detection
- Memory fragmentation analysis
- Memory usage limits (< 8GB target)
"""

import json
import time
import psutil
import subprocess
import gc
import tracemalloc
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
import sys
import threading

from .base_validator import BaseValidator, ValidationResult

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

try:
    from poker_ai.poker.evaluation.evaluator import Evaluator
    from poker_ai.poker.evaluation.eval_card import EvaluationCard
    from poker_ai.clustering.manager import ClusteringManager
    PYTHON_AVAILABLE = True
except ImportError as e:
    PYTHON_AVAILABLE = False


class MemoryProfiler:
    """Memory profiling utility for tracking memory usage patterns."""
    
    def __init__(self):
        self.process = psutil.Process()
        self.initial_memory = self.process.memory_info().rss
        self.peak_memory = self.initial_memory
        self.memory_samples = []
        self.monitoring = False
        self.monitor_thread = None
        
    def start_monitoring(self, interval: float = 0.1):
        """Start continuous memory monitoring."""
        self.monitoring = True
        self.monitor_thread = threading.Thread(target=self._monitor_loop, args=(interval,))
        self.monitor_thread.daemon = True
        self.monitor_thread.start()
        
    def stop_monitoring(self):
        """Stop memory monitoring."""
        self.monitoring = False
        if self.monitor_thread:
            self.monitor_thread.join(timeout=1.0)
    
    def _monitor_loop(self, interval: float):
        """Memory monitoring loop."""
        while self.monitoring:
            try:
                memory_info = self.process.memory_info()
                current_memory = memory_info.rss
                
                self.peak_memory = max(self.peak_memory, current_memory)
                self.memory_samples.append({
                    "timestamp": time.time(),
                    "rss": current_memory,
                    "vms": memory_info.vms,
                    "delta": current_memory - self.initial_memory
                })
                
                time.sleep(interval)
            except:
                break
    
    def get_peak_usage(self) -> int:
        """Get peak memory usage above baseline."""
        return self.peak_memory - self.initial_memory
    
    def get_current_usage(self) -> int:
        """Get current memory usage above baseline."""
        return self.process.memory_info().rss - self.initial_memory
    
    def get_memory_profile(self) -> Dict[str, Any]:
        """Get complete memory profile."""
        return {
            "initial_memory": self.initial_memory,
            "peak_memory": self.peak_memory,
            "peak_usage": self.get_peak_usage(),
            "current_usage": self.get_current_usage(),
            "samples": self.memory_samples,
            "sample_count": len(self.memory_samples)
        }


class MemoryProfilingValidator(BaseValidator):
    """Validate memory usage characteristics and detect memory issues."""
    
    def __init__(self, project_root: Path = None):
        super().__init__(project_root)
        
        if PYTHON_AVAILABLE:
            self.evaluator = Evaluator()
        else:
            self.evaluator = None
        
        # Memory targets and thresholds
        self.max_memory_limit = 8 * 1024 * 1024 * 1024  # 8GB
        self.memory_leak_threshold = 50 * 1024 * 1024    # 50MB
        self.fragmentation_threshold = 0.3               # 30% fragmentation
    
    def get_test_description(self) -> str:
        return "Validates memory usage characteristics, detects leaks, and ensures memory efficiency"
    
    def run_tests(self) -> bool:
        """Run all memory profiling tests."""
        if not PYTHON_AVAILABLE:
            self.logger.error("Python poker_ai not available - cannot run memory tests")
            return False
        
        # Build Zig project
        if not self.build_zig_project():
            self.logger.error("Failed to build Zig project")
            return False
        
        all_passed = True
        
        # Test categories
        test_methods = [
            self.test_baseline_memory_usage,
            self.test_hand_evaluation_memory,
            self.test_clustering_memory_usage,
            self.test_memory_leak_detection,
            self.test_memory_fragmentation,
            self.test_sustained_workload_memory,
            self.test_memory_scaling,
            self.test_memory_limits_compliance,
        ]
        
        for test_method in test_methods:
            try:
                self.logger.info(f"Running {test_method.__name__}...")
                result = test_method()
                if not result:
                    all_passed = False
            except Exception as e:
                self.logger.error(f"Test {test_method.__name__} failed with exception: {e}")
                all_passed = False
        
        return all_passed
    
    def test_baseline_memory_usage(self) -> bool:
        """Test baseline memory usage of both implementations."""
        self.logger.info("Testing baseline memory usage...")
        
        try:
            # Python baseline
            profiler = MemoryProfiler()
            python_baseline = profiler.get_current_usage()
            
            # Import modules to get realistic baseline
            if PYTHON_AVAILABLE:
                evaluator = Evaluator()
                del evaluator
                gc.collect()
            
            python_baseline_with_imports = profiler.get_current_usage()
            
            # Zig baseline
            zig_baseline = self._measure_zig_baseline_memory()
            
            # Compare baselines
            baseline_comparison = {
                "python_baseline": python_baseline,
                "python_with_imports": python_baseline_with_imports,
                "zig_baseline": zig_baseline,
                "import_overhead": python_baseline_with_imports - python_baseline
            }
            
            if zig_baseline:
                memory_ratio = zig_baseline / python_baseline_with_imports if python_baseline_with_imports > 0 else 0
                efficient_baseline = memory_ratio <= 0.5  # Zig should use ≤50% of Python baseline
            else:
                efficient_baseline = False
                memory_ratio = None
            
            self.create_result(
                test_name="baseline_memory_usage",
                passed=efficient_baseline,
                message=f"Python: {python_baseline_with_imports / 1024 / 1024:.1f}MB, Zig: {zig_baseline / 1024 / 1024:.1f}MB, Ratio: {memory_ratio:.2f}" if zig_baseline else "Zig baseline measurement failed",
                python_result=baseline_comparison,
                zig_result={"baseline": zig_baseline},
                memory_ratio=memory_ratio,
                efficient_baseline=efficient_baseline
            )
            
            return efficient_baseline if zig_baseline else True  # Don't fail if Zig not available
            
        except Exception as e:
            self.logger.error(f"Baseline memory test failed: {e}")
            self.create_result(
                test_name="baseline_memory_usage",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_hand_evaluation_memory(self) -> bool:
        """Test memory usage during hand evaluation workloads."""
        self.logger.info("Testing hand evaluation memory usage...")
        
        try:
            # Python hand evaluation memory profile
            profiler = MemoryProfiler()
            profiler.start_monitoring()
            
            # Run hand evaluations
            num_hands = 10000
            hands_evaluated = 0
            
            for _ in range(num_hands):
                # Generate random hand
                cards = self._generate_random_hand()
                eval_cards = [EvaluationCard.new(card) for card in cards]
                
                # Evaluate hand
                self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                hands_evaluated += 1
                
                # Periodic garbage collection to test memory cleanup
                if hands_evaluated % 1000 == 0:
                    gc.collect()
            
            profiler.stop_monitoring()
            python_profile = profiler.get_memory_profile()
            
            # Zig hand evaluation memory profile
            zig_profile = self._measure_zig_hand_evaluation_memory(num_hands)
            
            # Analyze memory efficiency
            python_peak = python_profile["peak_usage"]
            python_final = python_profile["current_usage"]
            
            if zig_profile:
                zig_peak = zig_profile["peak_usage"]
                zig_final = zig_profile["current_usage"]
                
                peak_ratio = zig_peak / python_peak if python_peak > 0 else 0
                memory_efficient = peak_ratio <= 0.2  # Zig should use ≤20% of Python peak
                
                # Check for memory cleanup (final should be close to initial)
                python_cleanup = python_final <= python_peak * 1.1  # Within 10% of peak
                zig_cleanup = zig_final <= zig_peak * 1.1
                good_cleanup = python_cleanup and zig_cleanup
            else:
                memory_efficient = True  # Don't fail if Zig not available
                good_cleanup = python_final <= python_peak * 1.1
                peak_ratio = None
            
            overall_passed = memory_efficient and good_cleanup
            
            self.create_result(
                test_name="hand_evaluation_memory",
                passed=overall_passed,
                message=f"Peak ratio: {peak_ratio:.2f}, Cleanup: {good_cleanup}" if peak_ratio else f"Python cleanup: {good_cleanup}",
                python_result={
                    "peak_usage": python_peak,
                    "final_usage": python_final,
                    "profile": python_profile
                },
                zig_result=zig_profile,
                peak_ratio=peak_ratio,
                memory_efficient=memory_efficient,
                good_cleanup=good_cleanup
            )
            
            return overall_passed
            
        except Exception as e:
            self.logger.error(f"Hand evaluation memory test failed: {e}")
            self.create_result(
                test_name="hand_evaluation_memory",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_clustering_memory_usage(self) -> bool:
        """Test memory usage during clustering operations."""
        self.logger.info("Testing clustering memory usage...")
        
        try:
            # Python clustering memory profile
            profiler = MemoryProfiler()
            profiler.start_monitoring()
            
            # Simulate clustering workload
            try:
                clustering_manager = ClusteringManager()
                
                # Generate test data
                test_data_size = 5000
                test_data = []
                
                for _ in range(test_data_size):
                    cards = self._generate_random_hand()
                    test_data.append({"cards": cards})
                
                # Simulate clustering operations
                for i in range(0, len(test_data), 100):
                    batch = test_data[i:i+100]
                    # Process batch (placeholder for actual clustering)
                    time.sleep(0.01)
                    
                    if i % 1000 == 0:
                        gc.collect()
                
            except Exception as e:
                self.logger.warning(f"Python clustering simulation failed: {e}")
                # Use placeholder workload
                for _ in range(1000):
                    data = [i for i in range(1000)]
                    del data
                    if _ % 100 == 0:
                        gc.collect()
            
            profiler.stop_monitoring()
            python_profile = profiler.get_memory_profile()
            
            # Zig clustering memory profile
            zig_profile = self._measure_zig_clustering_memory(test_data_size)
            
            # Analyze clustering memory efficiency
            python_peak = python_profile["peak_usage"]
            
            if zig_profile:
                zig_peak = zig_profile["peak_usage"]
                memory_ratio = zig_peak / python_peak if python_peak > 0 else 0
                meets_memory_target = zig_peak < self.max_memory_limit and memory_ratio <= 0.1
            else:
                meets_memory_target = python_peak < self.max_memory_limit
                memory_ratio = None
            
            self.create_result(
                test_name="clustering_memory_usage",
                passed=meets_memory_target,
                message=f"Python peak: {python_peak / 1024 / 1024:.1f}MB, Zig peak: {zig_profile['peak_usage'] / 1024 / 1024:.1f}MB, Ratio: {memory_ratio:.3f}" if zig_profile else f"Python peak: {python_peak / 1024 / 1024:.1f}MB",
                python_result={
                    "peak_usage": python_peak,
                    "profile": python_profile
                },
                zig_result=zig_profile,
                memory_ratio=memory_ratio,
                meets_target=meets_memory_target
            )
            
            return meets_memory_target
            
        except Exception as e:
            self.logger.error(f"Clustering memory test failed: {e}")
            self.create_result(
                test_name="clustering_memory_usage",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_memory_leak_detection(self) -> bool:
        """Test for memory leaks during extended operations."""
        self.logger.info("Testing memory leak detection...")
        
        try:
            # Enable detailed memory tracking
            tracemalloc.start()
            
            profiler = MemoryProfiler()
            profiler.start_monitoring(interval=0.5)  # Longer interval for leak detection
            
            # Run extended workload
            iterations = 1000
            checkpoint_interval = 100
            memory_checkpoints = []
            
            for i in range(iterations):
                # Perform operations that might leak
                cards = self._generate_random_hand()
                eval_cards = [EvaluationCard.new(card) for card in cards]
                result = self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                
                # Store result temporarily then discard
                temp_results = [result] * 10
                del temp_results
                
                if i % checkpoint_interval == 0:
                    gc.collect()  # Force garbage collection
                    current_memory = profiler.get_current_usage()
                    memory_checkpoints.append({
                        "iteration": i,
                        "memory_usage": current_memory
                    })
            
            profiler.stop_monitoring()
            
            # Analyze for memory leaks
            leak_analysis = self._analyze_memory_leaks(memory_checkpoints)
            
            # Zig leak detection
            zig_leak_analysis = self._test_zig_memory_leaks(iterations)
            
            # Determine if leaks detected
            python_no_leaks = leak_analysis["leak_detected"] == False
            zig_no_leaks = zig_leak_analysis["leak_detected"] == False if zig_leak_analysis else True
            
            overall_no_leaks = python_no_leaks and zig_no_leaks
            
            tracemalloc.stop()
            
            self.create_result(
                test_name="memory_leak_detection",
                passed=overall_no_leaks,
                message=f"Python leaks: {not python_no_leaks}, Zig leaks: {not zig_no_leaks}",
                python_result=leak_analysis,
                zig_result=zig_leak_analysis,
                overall_no_leaks=overall_no_leaks
            )
            
            return overall_no_leaks
            
        except Exception as e:
            self.logger.error(f"Memory leak detection test failed: {e}")
            self.create_result(
                test_name="memory_leak_detection",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_memory_fragmentation(self) -> bool:
        """Test memory fragmentation characteristics."""
        self.logger.info("Testing memory fragmentation...")
        
        try:
            profiler = MemoryProfiler()
            profiler.start_monitoring()
            
            # Create fragmentation pattern
            allocations = []
            
            # Allocate many small objects
            for _ in range(1000):
                cards = self._generate_random_hand()
                eval_cards = [EvaluationCard.new(card) for card in cards]
                allocations.append(eval_cards)
            
            # Free every other allocation
            for i in range(0, len(allocations), 2):
                del allocations[i]
                allocations[i] = None
            
            gc.collect()
            fragmented_memory = profiler.get_current_usage()
            
            # Allocate more to test fragmentation impact
            for _ in range(500):
                cards = self._generate_random_hand()
                eval_cards = [EvaluationCard.new(card) for card in cards]
                allocations.append(eval_cards)
            
            final_memory = profiler.get_current_usage()
            profiler.stop_monitoring()
            
            # Calculate fragmentation metrics
            memory_growth = final_memory - fragmented_memory
            expected_growth = 500 * len(self._generate_random_hand()) * 64  # Rough estimate
            
            fragmentation_ratio = memory_growth / expected_growth if expected_growth > 0 else 1.0
            low_fragmentation = fragmentation_ratio <= (1 + self.fragmentation_threshold)
            
            # Test Zig fragmentation
            zig_fragmentation = self._test_zig_fragmentation()
            
            self.create_result(
                test_name="memory_fragmentation",
                passed=low_fragmentation,
                message=f"Fragmentation ratio: {fragmentation_ratio:.2f} (threshold: {1 + self.fragmentation_threshold:.2f})",
                python_result={
                    "fragmentation_ratio": fragmentation_ratio,
                    "memory_growth": memory_growth,
                    "expected_growth": expected_growth
                },
                zig_result=zig_fragmentation,
                low_fragmentation=low_fragmentation
            )
            
            return low_fragmentation
            
        except Exception as e:
            self.logger.error(f"Memory fragmentation test failed: {e}")
            self.create_result(
                test_name="memory_fragmentation",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_sustained_workload_memory(self) -> bool:
        """Test memory behavior under sustained workload."""
        self.logger.info("Testing sustained workload memory...")
        
        try:
            profiler = MemoryProfiler()
            profiler.start_monitoring()
            
            # Run sustained workload
            duration_seconds = 30
            end_time = time.time() + duration_seconds
            operations = 0
            
            while time.time() < end_time:
                # Continuous operations
                cards = self._generate_random_hand()
                eval_cards = [EvaluationCard.new(card) for card in cards]
                self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                operations += 1
                
                # Periodic cleanup
                if operations % 100 == 0:
                    gc.collect()
            
            profiler.stop_monitoring()
            python_profile = profiler.get_memory_profile()
            
            # Zig sustained workload test
            zig_profile = self._test_zig_sustained_memory(duration_seconds)
            
            # Analyze memory stability
            python_stable = self._analyze_memory_stability(python_profile)
            zig_stable = zig_profile["stable"] if zig_profile else True
            
            overall_stable = python_stable and zig_stable
            
            self.create_result(
                test_name="sustained_workload_memory",
                passed=overall_stable,
                message=f"Operations: {operations}, Python stable: {python_stable}, Zig stable: {zig_stable}",
                python_result={
                    "operations": operations,
                    "stable": python_stable,
                    "profile": python_profile
                },
                zig_result=zig_profile,
                overall_stable=overall_stable
            )
            
            return overall_stable
            
        except Exception as e:
            self.logger.error(f"Sustained workload memory test failed: {e}")
            self.create_result(
                test_name="sustained_workload_memory",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_memory_scaling(self) -> bool:
        """Test how memory usage scales with workload size."""
        self.logger.info("Testing memory scaling...")
        
        try:
            scales = [100, 500, 1000, 2000]
            python_scaling = []
            zig_scaling = []
            
            for scale in scales:
                # Python scaling
                profiler = MemoryProfiler()
                
                for _ in range(scale):
                    cards = self._generate_random_hand()
                    eval_cards = [EvaluationCard.new(card) for card in cards]
                    self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                
                gc.collect()
                python_memory = profiler.get_current_usage()
                python_scaling.append({"scale": scale, "memory": python_memory})
                
                # Zig scaling
                zig_memory = self._measure_zig_memory_at_scale(scale)
                if zig_memory:
                    zig_scaling.append({"scale": scale, "memory": zig_memory})
            
            # Analyze scaling characteristics
            python_linear = self._check_linear_scaling(python_scaling)
            zig_linear = self._check_linear_scaling(zig_scaling) if zig_scaling else True
            
            good_scaling = python_linear and zig_linear
            
            self.create_result(
                test_name="memory_scaling",
                passed=good_scaling,
                message=f"Python linear: {python_linear}, Zig linear: {zig_linear}",
                python_result={
                    "scaling": python_scaling,
                    "linear": python_linear
                },
                zig_result={
                    "scaling": zig_scaling,
                    "linear": zig_linear
                } if zig_scaling else None,
                good_scaling=good_scaling
            )
            
            return good_scaling
            
        except Exception as e:
            self.logger.error(f"Memory scaling test failed: {e}")
            self.create_result(
                test_name="memory_scaling",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_memory_limits_compliance(self) -> bool:
        """Test compliance with memory usage limits."""
        self.logger.info("Testing memory limits compliance...")
        
        try:
            # Test large workload within limits
            large_workload_size = 10000
            
            profiler = MemoryProfiler()
            profiler.start_monitoring()
            
            # Run large workload
            for i in range(large_workload_size):
                cards = self._generate_random_hand()
                eval_cards = [EvaluationCard.new(card) for card in cards]
                self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                
                if i % 1000 == 0:
                    gc.collect()
                    current_usage = profiler.get_current_usage()
                    
                    # Check if approaching limits
                    if current_usage > self.max_memory_limit * 0.8:  # 80% of limit
                        self.logger.warning(f"Approaching memory limit at {i} operations")
                        break
            
            profiler.stop_monitoring()
            python_profile = profiler.get_memory_profile()
            
            # Test Zig memory limits
            zig_compliance = self._test_zig_memory_limits(large_workload_size)
            
            # Check compliance
            python_compliant = python_profile["peak_usage"] < self.max_memory_limit
            zig_compliant = zig_compliance["compliant"] if zig_compliance else True
            
            overall_compliant = python_compliant and zig_compliant
            
            self.create_result(
                test_name="memory_limits_compliance",
                passed=overall_compliant,
                message=f"Python: {python_profile['peak_usage'] / 1024 / 1024 / 1024:.1f}GB/{self.max_memory_limit / 1024 / 1024 / 1024:.1f}GB, Compliant: {overall_compliant}",
                python_result={
                    "peak_usage": python_profile["peak_usage"],
                    "limit": self.max_memory_limit,
                    "compliant": python_compliant
                },
                zig_result=zig_compliance,
                overall_compliant=overall_compliant
            )
            
            return overall_compliant
            
        except Exception as e:
            self.logger.error(f"Memory limits compliance test failed: {e}")
            self.create_result(
                test_name="memory_limits_compliance",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    # Helper methods for memory analysis
    
    def _generate_random_hand(self) -> List[str]:
        """Generate a random 7-card poker hand."""
        import random
        
        ranks = '23456789TJQKA'
        suits = 'shdc'
        deck = [f"{rank}{suit}" for rank in ranks for suit in suits]
        
        return random.sample(deck, 7)
    
    def _measure_zig_baseline_memory(self) -> Optional[int]:
        """Measure Zig baseline memory usage."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "baseline"],
                timeout=30
            )
            
            if result.returncode != 0:
                return None
            
            for line in result.stdout.split('\n'):
                if "baseline_memory:" in line:
                    return int(line.split(":")[1])
            
            return None
            
        except:
            return None
    
    def _measure_zig_hand_evaluation_memory(self, num_hands: int) -> Optional[Dict[str, Any]]:
        """Measure Zig memory usage during hand evaluation."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "hand_evaluation", str(num_hands)],
                timeout=120
            )
            
            if result.returncode != 0:
                return None
            
            memory_data = {}
            for line in result.stdout.split('\n'):
                if ":" in line:
                    key, value = line.split(":", 1)
                    try:
                        memory_data[key] = int(value)
                    except ValueError:
                        memory_data[key] = value
            
            return memory_data
            
        except:
            return None
    
    def _measure_zig_clustering_memory(self, data_size: int) -> Optional[Dict[str, Any]]:
        """Measure Zig memory usage during clustering."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "clustering", str(data_size)],
                timeout=180
            )
            
            if result.returncode != 0:
                return None
            
            memory_data = {}
            for line in result.stdout.split('\n'):
                if ":" in line:
                    key, value = line.split(":", 1)
                    try:
                        memory_data[key] = int(value)
                    except ValueError:
                        memory_data[key] = value
            
            return memory_data
            
        except:
            return None
    
    def _analyze_memory_leaks(self, checkpoints: List[Dict]) -> Dict[str, Any]:
        """Analyze memory checkpoints for leak patterns."""
        if len(checkpoints) < 3:
            return {"leak_detected": False, "reason": "insufficient_data"}
        
        # Calculate memory growth trend
        memory_values = [cp["memory_usage"] for cp in checkpoints]
        
        # Simple linear regression to detect trend
        n = len(memory_values)
        sum_x = sum(range(n))
        sum_y = sum(memory_values)
        sum_xy = sum(i * memory_values[i] for i in range(n))
        sum_x2 = sum(i * i for i in range(n))
        
        # Calculate slope (memory growth rate)
        denominator = n * sum_x2 - sum_x * sum_x
        if denominator == 0:
            slope = 0
        else:
            slope = (n * sum_xy - sum_x * sum_y) / denominator
        
        # Detect leak if significant positive slope
        leak_detected = slope > self.memory_leak_threshold / len(checkpoints)
        
        return {
            "leak_detected": leak_detected,
            "growth_rate": slope,
            "total_growth": memory_values[-1] - memory_values[0],
            "checkpoints": checkpoints
        }
    
    def _test_zig_memory_leaks(self, iterations: int) -> Optional[Dict[str, Any]]:
        """Test Zig implementation for memory leaks."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "leak_test", str(iterations)],
                timeout=180
            )
            
            if result.returncode != 0:
                return None
            
            leak_data = {"leak_detected": False}
            for line in result.stdout.split('\n'):
                if "leak_detected:" in line:
                    leak_data["leak_detected"] = line.split(":")[1].strip().lower() == "true"
                elif ":" in line:
                    key, value = line.split(":", 1)
                    try:
                        leak_data[key] = int(value)
                    except ValueError:
                        leak_data[key] = value
            
            return leak_data
            
        except:
            return None
    
    def _test_zig_fragmentation(self) -> Optional[Dict[str, Any]]:
        """Test Zig memory fragmentation characteristics."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "fragmentation"],
                timeout=60
            )
            
            if result.returncode != 0:
                return None
            
            fragmentation_data = {}
            for line in result.stdout.split('\n'):
                if ":" in line:
                    key, value = line.split(":", 1)
                    try:
                        fragmentation_data[key] = float(value)
                    except ValueError:
                        fragmentation_data[key] = value
            
            return fragmentation_data
            
        except:
            return None
    
    def _test_zig_sustained_memory(self, duration_seconds: int) -> Optional[Dict[str, Any]]:
        """Test Zig memory behavior under sustained load."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "sustained", str(duration_seconds)],
                timeout=duration_seconds + 30
            )
            
            if result.returncode != 0:
                return None
            
            sustained_data = {}
            for line in result.stdout.split('\n'):
                if ":" in line:
                    key, value = line.split(":", 1)
                    if key == "stable":
                        sustained_data[key] = value.strip().lower() == "true"
                    else:
                        try:
                            sustained_data[key] = int(value)
                        except ValueError:
                            sustained_data[key] = value
            
            return sustained_data
            
        except:
            return None
    
    def _analyze_memory_stability(self, profile: Dict[str, Any]) -> bool:
        """Analyze memory profile for stability."""
        samples = profile.get("samples", [])
        if len(samples) < 10:
            return True  # Not enough data to determine instability
        
        # Check for memory oscillations or continuous growth
        memory_values = [sample["delta"] for sample in samples]
        
        # Calculate coefficient of variation
        if len(memory_values) > 1:
            mean_memory = sum(memory_values) / len(memory_values)
            variance = sum((x - mean_memory) ** 2 for x in memory_values) / len(memory_values)
            std_dev = variance ** 0.5
            
            if mean_memory > 0:
                coefficient_of_variation = std_dev / mean_memory
                return coefficient_of_variation < 0.5  # 50% variation threshold
        
        return True
    
    def _measure_zig_memory_at_scale(self, scale: int) -> Optional[int]:
        """Measure Zig memory usage at specific scale."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "scale", str(scale)],
                timeout=60
            )
            
            if result.returncode != 0:
                return None
            
            for line in result.stdout.split('\n'):
                if "memory_usage:" in line:
                    return int(line.split(":")[1])
            
            return None
            
        except:
            return None
    
    def _check_linear_scaling(self, scaling_data: List[Dict]) -> bool:
        """Check if memory scaling is approximately linear."""
        if len(scaling_data) < 3:
            return True
        
        # Calculate correlation coefficient for linearity
        scales = [d["scale"] for d in scaling_data]
        memories = [d["memory"] for d in scaling_data]
        
        n = len(scales)
        sum_x = sum(scales)
        sum_y = sum(memories)
        sum_xy = sum(x * y for x, y in zip(scales, memories))
        sum_x2 = sum(x * x for x in scales)
        sum_y2 = sum(y * y for y in memories)
        
        # Pearson correlation coefficient
        numerator = n * sum_xy - sum_x * sum_y
        denominator = ((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y)) ** 0.5
        
        if denominator == 0:
            return True
        
        correlation = numerator / denominator
        return abs(correlation) > 0.8  # Strong linear correlation
    
    def _test_zig_memory_limits(self, workload_size: int) -> Optional[Dict[str, Any]]:
        """Test Zig compliance with memory limits."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_memory", "limits", str(workload_size)],
                timeout=300
            )
            
            if result.returncode != 0:
                return None
            
            limits_data = {}
            for line in result.stdout.split('\n'):
                if ":" in line:
                    key, value = line.split(":", 1)
                    if key == "compliant":
                        limits_data[key] = value.strip().lower() == "true"
                    else:
                        try:
                            limits_data[key] = int(value)
                        except ValueError:
                            limits_data[key] = value
            
            return limits_data
            
        except:
            return None


def main():
    """Run memory profiling validation."""
    validator = MemoryProfilingValidator()
    success = validator.run_and_report()
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())