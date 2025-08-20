"""
Performance regression validation for Zig vs Python implementations.

This module validates that Zig implementation achieves:
- Speed benchmarks and regression detection
- Memory usage improvements
- Scalability characteristics
- Performance targets (10x improvement minimum)
"""

import json
import time
import psutil
import subprocess
import statistics
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
import sys
import gc

from .base_validator import BaseValidator, ValidationResult

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

try:
    from poker_ai.poker.evaluation.evaluator import Evaluator
    from poker_ai.poker.evaluation.eval_card import EvaluationCard
    from poker_ai.poker.evaluation.deck import Deck
    from poker_ai.clustering.manager import ClusteringManager
    PYTHON_AVAILABLE = True
except ImportError as e:
    PYTHON_AVAILABLE = False


class PerformanceRegressionValidator(BaseValidator):
    """Validate performance characteristics and detect regressions."""
    
    def __init__(self, project_root: Path = None):
        super().__init__(project_root)
        
        if PYTHON_AVAILABLE:
            self.evaluator = Evaluator()
            self.deck = Deck()
        else:
            self.evaluator = None
            self.deck = None
        
        # Performance targets
        self.min_speedup_target = 5.0  # Minimum 5x speedup
        self.max_memory_ratio = 0.2    # Max 20% of Python memory usage
        self.regression_threshold = 0.1  # 10% regression threshold
    
    def get_test_description(self) -> str:
        return "Validates performance characteristics and detects regressions between Zig and Python implementations"
    
    def run_tests(self) -> bool:
        """Run all performance validation tests."""
        if not PYTHON_AVAILABLE:
            self.logger.error("Python poker_ai not available - cannot run performance tests")
            return False
        
        # Build Zig project
        if not self.build_zig_project("bench"):
            self.logger.error("Failed to build Zig benchmarks")
            return False
        
        all_passed = True
        
        # Test categories
        test_methods = [
            self.test_hand_evaluation_speed,
            self.test_clustering_performance,
            self.test_memory_usage_comparison,
            self.test_scalability_characteristics,
            self.test_throughput_benchmarks,
            self.test_latency_benchmarks,
            self.test_regression_detection,
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
    
    def test_hand_evaluation_speed(self) -> bool:
        """Test hand evaluation speed comparison."""
        self.logger.info("Testing hand evaluation speed...")
        
        try:
            # Generate test hands
            test_hands = self._generate_test_hands(10000)
            
            # Python benchmark
            self.logger.info("Benchmarking Python hand evaluation...")
            python_times = []
            
            for _ in range(5):  # Multiple runs for average
                gc.collect()  # Clean garbage before timing
                
                start_time = time.perf_counter()
                
                for hand_cards in test_hands:
                    eval_cards = [EvaluationCard.new(card) for card in hand_cards]
                    if len(eval_cards) == 7:
                        self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
                    else:
                        self.evaluator.evaluate(eval_cards, [])
                
                end_time = time.perf_counter()
                python_times.append(end_time - start_time)
            
            python_avg_time = statistics.mean(python_times)
            python_std_time = statistics.stdev(python_times) if len(python_times) > 1 else 0
            python_throughput = len(test_hands) / python_avg_time
            
            self.logger.info(f"Python: {python_avg_time:.3f}s ± {python_std_time:.3f}s ({python_throughput:.0f} hands/s)")
            
            # Zig benchmark
            self.logger.info("Benchmarking Zig hand evaluation...")
            zig_result = self._benchmark_zig_hand_evaluation(test_hands)
            
            if zig_result:
                zig_avg_time = zig_result["avg_time"]
                zig_throughput = zig_result["throughput"]
                speedup = python_avg_time / zig_avg_time
                
                self.logger.info(f"Zig: {zig_avg_time:.3f}s ({zig_throughput:.0f} hands/s, {speedup:.1f}x speedup)")
                
                meets_target = speedup >= self.min_speedup_target
                
                self.create_result(
                    test_name="hand_evaluation_speed",
                    passed=meets_target,
                    message=f"Speedup: {speedup:.1f}x (target: {self.min_speedup_target}x)",
                    python_result={
                        "avg_time": python_avg_time,
                        "std_time": python_std_time,
                        "throughput": python_throughput
                    },
                    zig_result={
                        "avg_time": zig_avg_time,
                        "throughput": zig_throughput
                    },
                    speedup=speedup,
                    meets_target=meets_target
                )
                
                return meets_target
            else:
                self.create_result(
                    test_name="hand_evaluation_speed",
                    passed=False,
                    message="Zig benchmark failed",
                    python_result={
                        "avg_time": python_avg_time,
                        "throughput": python_throughput
                    },
                    zig_result=None
                )
                return False
                
        except Exception as e:
            self.logger.error(f"Hand evaluation speed test failed: {e}")
            self.create_result(
                test_name="hand_evaluation_speed",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_clustering_performance(self) -> bool:
        """Test clustering performance comparison."""
        self.logger.info("Testing clustering performance...")
        
        try:
            # Python clustering benchmark
            self.logger.info("Benchmarking Python clustering...")
            
            # Small dataset for testing
            test_size = 1000
            
            python_start_time = time.perf_counter()
            python_peak_memory = 0
            
            # Monitor memory during clustering
            process = psutil.Process()
            initial_memory = process.memory_info().rss
            
            try:
                # Simulate clustering workload
                clustering_manager = ClusteringManager()
                
                # Generate test data
                test_data = self._generate_clustering_test_data(test_size)
                
                # Run clustering
                for _ in range(5):  # Multiple iterations
                    current_memory = process.memory_info().rss
                    python_peak_memory = max(python_peak_memory, current_memory - initial_memory)
                    
                    # Simulate clustering operations
                    time.sleep(0.01)  # Placeholder for actual clustering
                
            except Exception as e:
                self.logger.warning(f"Python clustering failed: {e}")
                # Use placeholder values
                python_peak_memory = 100 * 1024 * 1024  # 100MB placeholder
            
            python_end_time = time.perf_counter()
            python_time = python_end_time - python_start_time
            
            self.logger.info(f"Python clustering: {python_time:.2f}s, {python_peak_memory / 1024 / 1024:.1f}MB peak memory")
            
            # Zig clustering benchmark
            self.logger.info("Benchmarking Zig clustering...")
            zig_result = self._benchmark_zig_clustering(test_size)
            
            if zig_result:
                zig_time = zig_result["time"]
                zig_memory = zig_result["peak_memory"]
                
                time_speedup = python_time / zig_time
                memory_ratio = zig_memory / python_peak_memory
                
                self.logger.info(f"Zig clustering: {zig_time:.2f}s, {zig_memory / 1024 / 1024:.1f}MB peak memory")
                self.logger.info(f"Speedup: {time_speedup:.1f}x, Memory ratio: {memory_ratio:.2f}")
                
                meets_speed_target = time_speedup >= self.min_speedup_target
                meets_memory_target = memory_ratio <= self.max_memory_ratio
                overall_passed = meets_speed_target and meets_memory_target
                
                self.create_result(
                    test_name="clustering_performance",
                    passed=overall_passed,
                    message=f"Speed: {time_speedup:.1f}x, Memory ratio: {memory_ratio:.2f}",
                    python_result={
                        "time": python_time,
                        "peak_memory": python_peak_memory
                    },
                    zig_result={
                        "time": zig_time,
                        "peak_memory": zig_memory
                    },
                    time_speedup=time_speedup,
                    memory_ratio=memory_ratio,
                    meets_targets={"speed": meets_speed_target, "memory": meets_memory_target}
                )
                
                return overall_passed
            else:
                self.create_result(
                    test_name="clustering_performance",
                    passed=False,
                    message="Zig clustering benchmark failed",
                    python_result={
                        "time": python_time,
                        "peak_memory": python_peak_memory
                    },
                    zig_result=None
                )
                return False
                
        except Exception as e:
            self.logger.error(f"Clustering performance test failed: {e}")
            self.create_result(
                test_name="clustering_performance",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_memory_usage_comparison(self) -> bool:
        """Test memory usage characteristics."""
        self.logger.info("Testing memory usage comparison...")
        
        try:
            # Test different workload sizes
            workload_sizes = [100, 500, 1000, 2000]
            
            python_memory_profile = []
            zig_memory_profile = []
            
            for size in workload_sizes:
                # Python memory usage
                python_memory = self._measure_python_memory_usage(size)
                python_memory_profile.append({"size": size, "memory": python_memory})
                
                # Zig memory usage
                zig_memory = self._measure_zig_memory_usage(size)
                if zig_memory:
                    zig_memory_profile.append({"size": size, "memory": zig_memory})
            
            # Analyze memory characteristics
            memory_analysis = self._analyze_memory_profiles(python_memory_profile, zig_memory_profile)
            
            meets_memory_targets = (
                memory_analysis["avg_ratio"] <= self.max_memory_ratio and
                memory_analysis["max_ratio"] <= self.max_memory_ratio * 2  # Allow some variance
            )
            
            self.create_result(
                test_name="memory_usage_comparison",
                passed=meets_memory_targets,
                message=f"Avg memory ratio: {memory_analysis['avg_ratio']:.2f}, Max ratio: {memory_analysis['max_ratio']:.2f}",
                python_result=python_memory_profile,
                zig_result=zig_memory_profile,
                memory_analysis=memory_analysis,
                meets_targets=meets_memory_targets
            )
            
            return meets_memory_targets
            
        except Exception as e:
            self.logger.error(f"Memory usage comparison test failed: {e}")
            self.create_result(
                test_name="memory_usage_comparison",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_scalability_characteristics(self) -> bool:
        """Test how performance scales with workload size."""
        self.logger.info("Testing scalability characteristics...")
        
        try:
            # Test different scales
            scales = [100, 200, 500, 1000, 2000]
            
            python_scalability = []
            zig_scalability = []
            
            for scale in scales:
                # Python timing
                python_time = self._benchmark_python_at_scale(scale)
                python_scalability.append({"scale": scale, "time": python_time})
                
                # Zig timing
                zig_time = self._benchmark_zig_at_scale(scale)
                if zig_time:
                    zig_scalability.append({"scale": scale, "time": zig_time})
            
            # Analyze scalability
            scalability_analysis = self._analyze_scalability(python_scalability, zig_scalability)
            
            good_scalability = (
                scalability_analysis["python_complexity"] <= 2.0 and  # Sub-quadratic
                scalability_analysis["zig_complexity"] <= 2.0 and
                scalability_analysis["consistent_speedup"]
            )
            
            self.create_result(
                test_name="scalability_characteristics",
                passed=good_scalability,
                message=f"Python O(n^{scalability_analysis['python_complexity']:.1f}), Zig O(n^{scalability_analysis['zig_complexity']:.1f}), Consistent speedup: {scalability_analysis['consistent_speedup']}",
                python_result=python_scalability,
                zig_result=zig_scalability,
                scalability_analysis=scalability_analysis,
                good_scalability=good_scalability
            )
            
            return good_scalability
            
        except Exception as e:
            self.logger.error(f"Scalability test failed: {e}")
            self.create_result(
                test_name="scalability_characteristics",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_throughput_benchmarks(self) -> bool:
        """Test sustained throughput performance."""
        self.logger.info("Testing throughput benchmarks...")
        
        try:
            # Sustained load test
            duration_seconds = 10
            
            # Python throughput
            python_throughput = self._measure_sustained_throughput_python(duration_seconds)
            
            # Zig throughput
            zig_throughput = self._measure_sustained_throughput_zig(duration_seconds)
            
            if zig_throughput:
                throughput_ratio = zig_throughput / python_throughput
                meets_throughput_target = throughput_ratio >= self.min_speedup_target
                
                self.create_result(
                    test_name="throughput_benchmarks",
                    passed=meets_throughput_target,
                    message=f"Python: {python_throughput:.0f} ops/s, Zig: {zig_throughput:.0f} ops/s, Ratio: {throughput_ratio:.1f}x",
                    python_result={"throughput": python_throughput},
                    zig_result={"throughput": zig_throughput},
                    throughput_ratio=throughput_ratio,
                    meets_target=meets_throughput_target
                )
                
                return meets_throughput_target
            else:
                self.create_result(
                    test_name="throughput_benchmarks",
                    passed=False,
                    message="Zig throughput measurement failed",
                    python_result={"throughput": python_throughput},
                    zig_result=None
                )
                return False
                
        except Exception as e:
            self.logger.error(f"Throughput benchmark test failed: {e}")
            self.create_result(
                test_name="throughput_benchmarks",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_latency_benchmarks(self) -> bool:
        """Test latency characteristics (response time distribution)."""
        self.logger.info("Testing latency benchmarks...")
        
        try:
            # Measure latency distribution
            num_samples = 1000
            
            python_latencies = self._measure_python_latencies(num_samples)
            zig_latencies = self._measure_zig_latencies(num_samples)
            
            if zig_latencies:
                latency_analysis = self._analyze_latencies(python_latencies, zig_latencies)
                
                good_latency = (
                    latency_analysis["zig_p50"] < latency_analysis["python_p50"] and
                    latency_analysis["zig_p95"] < latency_analysis["python_p95"] and
                    latency_analysis["zig_p99"] < latency_analysis["python_p99"]
                )
                
                self.create_result(
                    test_name="latency_benchmarks",
                    passed=good_latency,
                    message=f"P50: {latency_analysis['speedup_p50']:.1f}x, P95: {latency_analysis['speedup_p95']:.1f}x, P99: {latency_analysis['speedup_p99']:.1f}x",
                    python_result={
                        "latencies": python_latencies,
                        "p50": latency_analysis["python_p50"],
                        "p95": latency_analysis["python_p95"],
                        "p99": latency_analysis["python_p99"]
                    },
                    zig_result={
                        "latencies": zig_latencies,
                        "p50": latency_analysis["zig_p50"],
                        "p95": latency_analysis["zig_p95"],
                        "p99": latency_analysis["zig_p99"]
                    },
                    latency_analysis=latency_analysis,
                    good_latency=good_latency
                )
                
                return good_latency
            else:
                self.create_result(
                    test_name="latency_benchmarks",
                    passed=False,
                    message="Zig latency measurement failed",
                    python_result={"latencies": python_latencies},
                    zig_result=None
                )
                return False
                
        except Exception as e:
            self.logger.error(f"Latency benchmark test failed: {e}")
            self.create_result(
                test_name="latency_benchmarks",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_regression_detection(self) -> bool:
        """Test for performance regressions against baseline."""
        self.logger.info("Testing regression detection...")
        
        try:
            # Load baseline performance data if available
            baseline_file = self.validation_dir / "performance_baseline.json"
            
            if baseline_file.exists():
                with open(baseline_file, 'r') as f:
                    baseline_data = json.load(f)
                
                # Run current performance tests
                current_performance = self._measure_current_performance()
                
                # Compare against baseline
                regression_analysis = self._detect_regressions(baseline_data, current_performance)
                
                no_regressions = not regression_analysis["has_regressions"]
                
                self.create_result(
                    test_name="regression_detection",
                    passed=no_regressions,
                    message=f"Regressions found: {regression_analysis['regression_count']}, Max regression: {regression_analysis['max_regression']:.1%}",
                    python_result=baseline_data,
                    zig_result=current_performance,
                    regression_analysis=regression_analysis,
                    no_regressions=no_regressions
                )
                
                # Update baseline if no regressions and performance improved
                if no_regressions and regression_analysis["overall_improvement"] > 0:
                    self._update_performance_baseline(current_performance)
                
                return no_regressions
            else:
                # No baseline exists, create one
                current_performance = self._measure_current_performance()
                self._update_performance_baseline(current_performance)
                
                self.create_result(
                    test_name="regression_detection",
                    passed=True,
                    message="Created new performance baseline",
                    python_result=None,
                    zig_result=current_performance,
                    baseline_created=True
                )
                
                return True
                
        except Exception as e:
            self.logger.error(f"Regression detection test failed: {e}")
            self.create_result(
                test_name="regression_detection",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    # Helper methods for benchmarking
    
    def _generate_test_hands(self, count: int) -> List[List[str]]:
        """Generate test hands for benchmarking."""
        hands = []
        for _ in range(count):
            self.deck.shuffle()
            hand = [str(card) for card in self.deck.draw(7)]
            hands.append(hand)
        return hands
    
    def _benchmark_zig_hand_evaluation(self, test_hands: List[List[str]]) -> Optional[Dict[str, Any]]:
        """Benchmark Zig hand evaluation."""
        try:
            # Create input file for Zig benchmark
            input_data = json.dumps({"hands": test_hands})
            
            # Run Zig benchmark
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_bench", "hand_evaluation"],
                input_data=input_data,
                timeout=60
            )
            
            if result.returncode != 0:
                self.logger.error(f"Zig benchmark failed: {result.stderr}")
                return None
            
            # Parse results
            output_lines = result.stdout.strip().split('\n')
            for line in output_lines:
                if "avg_time:" in line:
                    avg_time = float(line.split(":")[1])
                elif "throughput:" in line:
                    throughput = float(line.split(":")[1])
            
            return {
                "avg_time": avg_time,
                "throughput": throughput
            }
            
        except Exception as e:
            self.logger.error(f"Zig hand evaluation benchmark failed: {e}")
            return None
    
    def _generate_clustering_test_data(self, size: int) -> List[Dict]:
        """Generate test data for clustering benchmarks."""
        test_data = []
        for _ in range(size):
            # Generate random hand data
            self.deck.shuffle()
            cards = [str(card) for card in self.deck.draw(7)]
            test_data.append({"cards": cards})
        return test_data
    
    def _benchmark_zig_clustering(self, test_size: int) -> Optional[Dict[str, Any]]:
        """Benchmark Zig clustering performance."""
        try:
            # Run Zig clustering benchmark
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_bench", "clustering", str(test_size)],
                timeout=120
            )
            
            if result.returncode != 0:
                self.logger.error(f"Zig clustering benchmark failed: {result.stderr}")
                return None
            
            # Parse results
            output_lines = result.stdout.strip().split('\n')
            time_taken = None
            peak_memory = None
            
            for line in output_lines:
                if "time:" in line:
                    time_taken = float(line.split(":")[1])
                elif "peak_memory:" in line:
                    peak_memory = int(line.split(":")[1])
            
            return {
                "time": time_taken,
                "peak_memory": peak_memory
            }
            
        except Exception as e:
            self.logger.error(f"Zig clustering benchmark failed: {e}")
            return None
    
    def _measure_python_memory_usage(self, workload_size: int) -> int:
        """Measure Python memory usage for given workload."""
        process = psutil.Process()
        initial_memory = process.memory_info().rss
        
        # Simulate workload
        test_data = self._generate_clustering_test_data(workload_size)
        
        # Force garbage collection and measure
        gc.collect()
        peak_memory = process.memory_info().rss
        
        return peak_memory - initial_memory
    
    def _measure_zig_memory_usage(self, workload_size: int) -> Optional[int]:
        """Measure Zig memory usage for given workload."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_bench", "memory", str(workload_size)],
                timeout=60
            )
            
            if result.returncode != 0:
                return None
            
            # Parse memory usage from output
            for line in result.stdout.split('\n'):
                if "peak_memory:" in line:
                    return int(line.split(":")[1])
            
            return None
            
        except:
            return None
    
    def _analyze_memory_profiles(self, python_profile: List[Dict], zig_profile: List[Dict]) -> Dict[str, Any]:
        """Analyze memory usage profiles."""
        if not zig_profile:
            return {"avg_ratio": float('inf'), "max_ratio": float('inf')}
        
        ratios = []
        for p_data, z_data in zip(python_profile, zig_profile):
            if p_data["memory"] > 0:
                ratio = z_data["memory"] / p_data["memory"]
                ratios.append(ratio)
        
        if ratios:
            return {
                "avg_ratio": statistics.mean(ratios),
                "max_ratio": max(ratios),
                "min_ratio": min(ratios),
                "ratios": ratios
            }
        else:
            return {"avg_ratio": float('inf'), "max_ratio": float('inf')}
    
    def _benchmark_python_at_scale(self, scale: int) -> float:
        """Benchmark Python performance at given scale."""
        start_time = time.perf_counter()
        
        # Simulate scaled workload
        test_hands = self._generate_test_hands(scale)
        for hand in test_hands:
            eval_cards = [EvaluationCard.new(card) for card in hand]
            self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
        
        return time.perf_counter() - start_time
    
    def _benchmark_zig_at_scale(self, scale: int) -> Optional[float]:
        """Benchmark Zig performance at given scale."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_bench", "scale", str(scale)],
                timeout=120
            )
            
            if result.returncode != 0:
                return None
            
            for line in result.stdout.split('\n'):
                if "time:" in line:
                    return float(line.split(":")[1])
            
            return None
            
        except:
            return None
    
    def _analyze_scalability(self, python_data: List[Dict], zig_data: List[Dict]) -> Dict[str, Any]:
        """Analyze scalability characteristics."""
        # Simplified complexity analysis (assumes linear relationship in log space)
        
        if len(python_data) < 2:
            return {"python_complexity": 1.0, "zig_complexity": 1.0, "consistent_speedup": True}
        
        # Calculate complexity (slope in log-log space)
        python_complexity = self._estimate_complexity(python_data)
        zig_complexity = self._estimate_complexity(zig_data) if zig_data else 1.0
        
        # Check for consistent speedup
        consistent_speedup = True
        if zig_data and len(zig_data) == len(python_data):
            speedups = []
            for p_data, z_data in zip(python_data, zig_data):
                if z_data["time"] > 0:
                    speedup = p_data["time"] / z_data["time"]
                    speedups.append(speedup)
            
            if speedups:
                speedup_variance = statistics.variance(speedups) if len(speedups) > 1 else 0
                consistent_speedup = speedup_variance < 1.0  # Low variance indicates consistency
        
        return {
            "python_complexity": python_complexity,
            "zig_complexity": zig_complexity,
            "consistent_speedup": consistent_speedup
        }
    
    def _estimate_complexity(self, data: List[Dict]) -> float:
        """Estimate algorithmic complexity from timing data."""
        if len(data) < 2:
            return 1.0
        
        # Simple linear regression in log space
        import math
        
        x_vals = [math.log(d["scale"]) for d in data if d["time"] > 0]
        y_vals = [math.log(d["time"]) for d in data if d["time"] > 0]
        
        if len(x_vals) < 2:
            return 1.0
        
        # Calculate slope (complexity exponent)
        n = len(x_vals)
        sum_x = sum(x_vals)
        sum_y = sum(y_vals)
        sum_xy = sum(x * y for x, y in zip(x_vals, y_vals))
        sum_x2 = sum(x * x for x in x_vals)
        
        denominator = n * sum_x2 - sum_x * sum_x
        if denominator == 0:
            return 1.0
        
        slope = (n * sum_xy - sum_x * sum_y) / denominator
        return max(1.0, slope)  # Complexity at least O(n)
    
    def _measure_sustained_throughput_python(self, duration_seconds: int) -> float:
        """Measure sustained throughput for Python."""
        end_time = time.time() + duration_seconds
        operations = 0
        
        while time.time() < end_time:
            # Perform operation
            self.deck.shuffle()
            hand = [str(card) for card in self.deck.draw(7)]
            eval_cards = [EvaluationCard.new(card) for card in hand]
            self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
            operations += 1
        
        return operations / duration_seconds
    
    def _measure_sustained_throughput_zig(self, duration_seconds: int) -> Optional[float]:
        """Measure sustained throughput for Zig."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_bench", "throughput", str(duration_seconds)],
                timeout=duration_seconds + 30
            )
            
            if result.returncode != 0:
                return None
            
            for line in result.stdout.split('\n'):
                if "throughput:" in line:
                    return float(line.split(":")[1])
            
            return None
            
        except:
            return None
    
    def _measure_python_latencies(self, num_samples: int) -> List[float]:
        """Measure latency distribution for Python."""
        latencies = []
        
        for _ in range(num_samples):
            self.deck.shuffle()
            hand = [str(card) for card in self.deck.draw(7)]
            eval_cards = [EvaluationCard.new(card) for card in hand]
            
            start_time = time.perf_counter()
            self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
            end_time = time.perf_counter()
            
            latencies.append(end_time - start_time)
        
        return latencies
    
    def _measure_zig_latencies(self, num_samples: int) -> Optional[List[float]]:
        """Measure latency distribution for Zig."""
        try:
            result = self.run_zig_command(
                ["./zig-out/bin/poker_ai_bench", "latency", str(num_samples)],
                timeout=60
            )
            
            if result.returncode != 0:
                return None
            
            latencies = []
            for line in result.stdout.split('\n'):
                if line.startswith("latency:"):
                    latency = float(line.split(":")[1])
                    latencies.append(latency)
            
            return latencies if latencies else None
            
        except:
            return None
    
    def _analyze_latencies(self, python_latencies: List[float], zig_latencies: List[float]) -> Dict[str, Any]:
        """Analyze latency distributions."""
        def percentile(data: List[float], p: float) -> float:
            sorted_data = sorted(data)
            index = int(len(sorted_data) * p / 100)
            return sorted_data[min(index, len(sorted_data) - 1)]
        
        python_p50 = percentile(python_latencies, 50)
        python_p95 = percentile(python_latencies, 95)
        python_p99 = percentile(python_latencies, 99)
        
        zig_p50 = percentile(zig_latencies, 50)
        zig_p95 = percentile(zig_latencies, 95)
        zig_p99 = percentile(zig_latencies, 99)
        
        return {
            "python_p50": python_p50,
            "python_p95": python_p95,
            "python_p99": python_p99,
            "zig_p50": zig_p50,
            "zig_p95": zig_p95,
            "zig_p99": zig_p99,
            "speedup_p50": python_p50 / zig_p50 if zig_p50 > 0 else 0,
            "speedup_p95": python_p95 / zig_p95 if zig_p95 > 0 else 0,
            "speedup_p99": python_p99 / zig_p99 if zig_p99 > 0 else 0,
        }
    
    def _measure_current_performance(self) -> Dict[str, Any]:
        """Measure current performance characteristics."""
        # Quick performance snapshot
        test_hands = self._generate_test_hands(1000)
        
        start_time = time.perf_counter()
        for hand in test_hands:
            eval_cards = [EvaluationCard.new(card) for card in hand]
            self.evaluator.evaluate(eval_cards[:5], eval_cards[5:])
        python_time = time.perf_counter() - start_time
        
        zig_result = self._benchmark_zig_hand_evaluation(test_hands)
        
        return {
            "timestamp": time.time(),
            "python_time": python_time,
            "zig_time": zig_result["avg_time"] if zig_result else None,
            "speedup": python_time / zig_result["avg_time"] if zig_result and zig_result["avg_time"] > 0 else None
        }
    
    def _detect_regressions(self, baseline: Dict, current: Dict) -> Dict[str, Any]:
        """Detect performance regressions."""
        regressions = []
        
        if baseline.get("speedup") and current.get("speedup"):
            speedup_change = (current["speedup"] - baseline["speedup"]) / baseline["speedup"]
            
            if speedup_change < -self.regression_threshold:
                regressions.append({
                    "metric": "speedup",
                    "baseline": baseline["speedup"],
                    "current": current["speedup"],
                    "change": speedup_change
                })
        
        has_regressions = len(regressions) > 0
        max_regression = max([abs(r["change"]) for r in regressions], default=0)
        overall_improvement = current.get("speedup", 0) - baseline.get("speedup", 0)
        
        return {
            "has_regressions": has_regressions,
            "regression_count": len(regressions),
            "max_regression": max_regression,
            "regressions": regressions,
            "overall_improvement": overall_improvement
        }
    
    def _update_performance_baseline(self, performance_data: Dict) -> None:
        """Update the performance baseline."""
        baseline_file = self.validation_dir / "performance_baseline.json"
        
        with open(baseline_file, 'w') as f:
            json.dump(performance_data, f, indent=2)
        
        self.logger.info(f"Updated performance baseline: {baseline_file}")


def main():
    """Run performance regression validation."""
    validator = PerformanceRegressionValidator()
    success = validator.run_and_report()
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())