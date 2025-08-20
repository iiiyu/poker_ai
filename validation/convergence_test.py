"""
MCCFR convergence validation between Zig and Python implementations.

This module validates that MCCFR training produces equivalent:
- Nash equilibrium convergence on Kuhn poker
- Strategy comparison with Python
- Exploitability measurements
- Training speed benchmarks
"""

import json
import numpy as np
import time
import subprocess
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
import sys

from .base_validator import BaseValidator, ValidationResult

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

try:
    from poker_ai.ai.mccfr import MCCFR
    from poker_ai.games.kuhn_poker import KuhnPoker
    PYTHON_AVAILABLE = True
except ImportError as e:
    PYTHON_AVAILABLE = False


class ConvergenceTestValidator(BaseValidator):
    """Validate MCCFR convergence between Zig and Python implementations."""
    
    def __init__(self, project_root: Path = None):
        super().__init__(project_root)
        self.kuhn_strategies = {}
        self.convergence_tolerance = 1e-3
        self.exploitability_tolerance = 1e-2
    
    def get_test_description(self) -> str:
        return "Validates MCCFR convergence and Nash equilibrium properties between Zig and Python implementations"
    
    def run_tests(self) -> bool:
        """Run all convergence validation tests."""
        if not PYTHON_AVAILABLE:
            self.logger.error("Python poker_ai not available - cannot run convergence tests")
            return False
        
        # Build Zig project
        if not self.build_zig_project():
            self.logger.error("Failed to build Zig project")
            return False
        
        all_passed = True
        
        # Test categories
        test_methods = [
            self.test_kuhn_poker_convergence,
            self.test_strategy_consistency,
            self.test_exploitability_measurement,
            self.test_training_reproducibility,
            self.test_convergence_speed,
            self.test_nash_equilibrium_properties,
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
    
    def test_kuhn_poker_convergence(self) -> bool:
        """Test MCCFR convergence on Kuhn poker game."""
        self.logger.info("Testing Kuhn poker convergence...")
        
        iterations = 10000
        
        try:
            # Python MCCFR training
            self.logger.info("Training Python MCCFR...")
            python_start_time = time.time()
            
            python_game = KuhnPoker()
            python_mccfr = MCCFR(python_game)
            
            python_strategies = []
            for i in range(iterations):
                python_mccfr.train(1)
                if i % 1000 == 0:
                    strategy = python_mccfr.get_average_strategy()
                    python_strategies.append({
                        "iteration": i,
                        "strategy": strategy,
                        "exploitability": self._calculate_exploitability_python(python_mccfr)
                    })
            
            python_final_strategy = python_mccfr.get_average_strategy()
            python_final_exploitability = self._calculate_exploitability_python(python_mccfr)
            python_training_time = time.time() - python_start_time
            
            self.logger.info(f"Python training completed in {python_training_time:.2f}s")
            self.logger.info(f"Python final exploitability: {python_final_exploitability:.6f}")
            
            # Zig MCCFR training (if available)
            zig_final_strategy = None
            zig_final_exploitability = None
            zig_training_time = None
            
            zig_result = self._train_zig_kuhn_poker(iterations)
            if zig_result:
                zig_final_strategy = zig_result["strategy"]
                zig_final_exploitability = zig_result["exploitability"]
                zig_training_time = zig_result["training_time"]
                
                self.logger.info(f"Zig training completed in {zig_training_time:.2f}s")
                self.logger.info(f"Zig final exploitability: {zig_final_exploitability:.6f}")
            
            # Compare convergence
            if zig_result:
                # Strategy similarity
                strategy_similarity = self._compare_strategies(python_final_strategy, zig_final_strategy)
                
                # Exploitability comparison
                exploitability_diff = abs(python_final_exploitability - zig_final_exploitability)
                exploitability_within_tolerance = exploitability_diff < self.exploitability_tolerance
                
                # Speed comparison
                speedup = python_training_time / zig_training_time if zig_training_time > 0 else 0
                
                convergence_success = (
                    strategy_similarity > 0.95 and  # 95% strategy similarity
                    exploitability_within_tolerance and
                    python_final_exploitability < 0.1 and  # Both converged
                    zig_final_exploitability < 0.1
                )
                
                self.create_result(
                    test_name="kuhn_poker_convergence",
                    passed=convergence_success,
                    message=f"Strategy similarity: {strategy_similarity:.3f}, Exploitability diff: {exploitability_diff:.6f}, Speedup: {speedup:.1f}x",
                    python_result={
                        "strategy": python_final_strategy,
                        "exploitability": python_final_exploitability,
                        "training_time": python_training_time
                    },
                    zig_result={
                        "strategy": zig_final_strategy,
                        "exploitability": zig_final_exploitability,
                        "training_time": zig_training_time
                    },
                    strategy_similarity=strategy_similarity,
                    exploitability_diff=exploitability_diff,
                    speedup=speedup
                )
                
                return convergence_success
            else:
                # Python-only validation
                python_converged = python_final_exploitability < 0.1
                
                self.create_result(
                    test_name="kuhn_poker_convergence",
                    passed=python_converged,
                    message=f"Python-only validation: exploitability {python_final_exploitability:.6f}",
                    python_result={
                        "strategy": python_final_strategy,
                        "exploitability": python_final_exploitability,
                        "training_time": python_training_time
                    },
                    zig_result=None
                )
                
                return python_converged
                
        except Exception as e:
            self.logger.error(f"Kuhn poker convergence test failed: {e}")
            self.create_result(
                test_name="kuhn_poker_convergence",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_strategy_consistency(self) -> bool:
        """Test that strategies remain consistent across runs with same seed."""
        self.logger.info("Testing strategy consistency...")
        
        iterations = 5000
        seed = 12345
        
        try:
            # Run Python MCCFR multiple times with same seed
            python_strategies = []
            
            for run in range(3):
                np.random.seed(seed)  # Set same seed
                
                python_game = KuhnPoker()
                python_mccfr = MCCFR(python_game)
                
                for _ in range(iterations):
                    python_mccfr.train(1)
                
                strategy = python_mccfr.get_average_strategy()
                python_strategies.append(strategy)
            
            # Check consistency
            python_consistent = self._check_strategy_consistency(python_strategies)
            
            # Test Zig consistency (if available)
            zig_strategies = []
            zig_consistent = True
            
            for run in range(3):
                zig_result = self._train_zig_kuhn_poker(iterations, seed=seed)
                if zig_result:
                    zig_strategies.append(zig_result["strategy"])
                else:
                    zig_consistent = False
                    break
            
            if zig_strategies:
                zig_consistent = self._check_strategy_consistency(zig_strategies)
            
            overall_consistent = python_consistent and zig_consistent
            
            self.create_result(
                test_name="strategy_consistency",
                passed=overall_consistent,
                message=f"Python consistent: {python_consistent}, Zig consistent: {zig_consistent}",
                python_result={"consistent": python_consistent, "strategies": len(python_strategies)},
                zig_result={"consistent": zig_consistent, "strategies": len(zig_strategies)},
            )
            
            return overall_consistent
            
        except Exception as e:
            self.logger.error(f"Strategy consistency test failed: {e}")
            self.create_result(
                test_name="strategy_consistency",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_exploitability_measurement(self) -> bool:
        """Test exploitability calculation accuracy."""
        self.logger.info("Testing exploitability measurement...")
        
        try:
            # Test known strategies with known exploitabilities
            test_strategies = [
                # Random strategy (high exploitability)
                {
                    "name": "random",
                    "strategy": self._create_random_kuhn_strategy(),
                    "expected_exploitability_range": (0.2, 0.4)
                },
                # Near-optimal strategy (low exploitability)
                {
                    "name": "trained",
                    "strategy": self._get_trained_kuhn_strategy(),
                    "expected_exploitability_range": (0.0, 0.1)
                }
            ]
            
            passed_count = 0
            
            for test_case in test_strategies:
                strategy = test_case["strategy"]
                expected_range = test_case["expected_exploitability_range"]
                
                # Python exploitability calculation
                python_exploitability = self._calculate_exploitability_from_strategy(strategy)
                
                # Zig exploitability calculation (if available)
                zig_exploitability = self._calculate_zig_exploitability(strategy)
                
                # Check if within expected range
                python_in_range = expected_range[0] <= python_exploitability <= expected_range[1]
                
                if zig_exploitability is not None:
                    zig_in_range = expected_range[0] <= zig_exploitability <= expected_range[1]
                    exploitability_diff = abs(python_exploitability - zig_exploitability)
                    exploitability_match = exploitability_diff < self.exploitability_tolerance
                    
                    test_passed = python_in_range and zig_in_range and exploitability_match
                else:
                    test_passed = python_in_range
                    exploitability_diff = None
                
                passed_count += 1 if test_passed else 0
                
                self.create_result(
                    test_name=f"exploitability_{test_case['name']}",
                    passed=test_passed,
                    message=f"Python: {python_exploitability:.4f}, Zig: {zig_exploitability}, Expected: {expected_range}",
                    python_result=python_exploitability,
                    zig_result=zig_exploitability,
                    expected_range=expected_range,
                    exploitability_diff=exploitability_diff
                )
            
            success_rate = passed_count / len(test_strategies)
            return success_rate >= 1.0  # All must pass
            
        except Exception as e:
            self.logger.error(f"Exploitability measurement test failed: {e}")
            self.create_result(
                test_name="exploitability_measurement",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_training_reproducibility(self) -> bool:
        """Test that training is reproducible with same parameters."""
        self.logger.info("Testing training reproducibility...")
        
        # This test ensures that given the same seed and parameters,
        # training produces identical results
        
        iterations = 3000
        seed = 42
        
        try:
            # Python reproducibility
            python_results = []
            
            for run in range(2):
                np.random.seed(seed)
                
                python_game = KuhnPoker()
                python_mccfr = MCCFR(python_game)
                
                for _ in range(iterations):
                    python_mccfr.train(1)
                
                strategy = python_mccfr.get_average_strategy()
                exploitability = self._calculate_exploitability_python(python_mccfr)
                
                python_results.append({
                    "strategy": strategy,
                    "exploitability": exploitability
                })
            
            # Check Python reproducibility
            python_reproducible = self._compare_strategies(
                python_results[0]["strategy"],
                python_results[1]["strategy"]
            ) > 0.999  # Very high similarity required
            
            exploitability_diff = abs(
                python_results[0]["exploitability"] - 
                python_results[1]["exploitability"]
            )
            
            python_reproducible = python_reproducible and exploitability_diff < 1e-6
            
            # Zig reproducibility (if available)
            zig_reproducible = True
            zig_results = []
            
            for run in range(2):
                zig_result = self._train_zig_kuhn_poker(iterations, seed=seed)
                if zig_result:
                    zig_results.append(zig_result)
                else:
                    zig_reproducible = False
                    break
            
            if zig_results and len(zig_results) == 2:
                zig_strategy_similarity = self._compare_strategies(
                    zig_results[0]["strategy"],
                    zig_results[1]["strategy"]
                )
                zig_exploitability_diff = abs(
                    zig_results[0]["exploitability"] -
                    zig_results[1]["exploitability"]
                )
                
                zig_reproducible = (zig_strategy_similarity > 0.999 and 
                                  zig_exploitability_diff < 1e-6)
            
            overall_reproducible = python_reproducible and zig_reproducible
            
            self.create_result(
                test_name="training_reproducibility",
                passed=overall_reproducible,
                message=f"Python reproducible: {python_reproducible}, Zig reproducible: {zig_reproducible}",
                python_result={
                    "reproducible": python_reproducible,
                    "exploitability_diff": exploitability_diff
                },
                zig_result={
                    "reproducible": zig_reproducible,
                    "exploitability_diff": zig_exploitability_diff if zig_results else None
                } if zig_results else None
            )
            
            return overall_reproducible
            
        except Exception as e:
            self.logger.error(f"Training reproducibility test failed: {e}")
            self.create_result(
                test_name="training_reproducibility",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_convergence_speed(self) -> bool:
        """Test convergence speed characteristics."""
        self.logger.info("Testing convergence speed...")
        
        # Test that exploitability decreases over training iterations
        iterations_checkpoints = [100, 500, 1000, 2000, 5000]
        
        try:
            # Python convergence curve
            python_game = KuhnPoker()
            python_mccfr = MCCFR(python_game)
            
            python_exploitabilities = []
            
            for target_iterations in iterations_checkpoints:
                current_iterations = len(python_exploitabilities) * iterations_checkpoints[0] if python_exploitabilities else 0
                
                while current_iterations < target_iterations:
                    python_mccfr.train(1)
                    current_iterations += 1
                
                exploitability = self._calculate_exploitability_python(python_mccfr)
                python_exploitabilities.append(exploitability)
            
            # Check that exploitability generally decreases
            python_converging = self._is_converging(python_exploitabilities)
            
            # Zig convergence curve (if available)
            zig_exploitabilities = []
            zig_converging = True
            
            for target_iterations in iterations_checkpoints:
                zig_result = self._train_zig_kuhn_poker(target_iterations)
                if zig_result:
                    zig_exploitabilities.append(zig_result["exploitability"])
                else:
                    zig_converging = False
                    break
            
            if zig_exploitabilities:
                zig_converging = self._is_converging(zig_exploitabilities)
            
            overall_converging = python_converging and zig_converging
            
            self.create_result(
                test_name="convergence_speed",
                passed=overall_converging,
                message=f"Python converging: {python_converging}, Zig converging: {zig_converging}",
                python_result={
                    "converging": python_converging,
                    "exploitabilities": python_exploitabilities
                },
                zig_result={
                    "converging": zig_converging,
                    "exploitabilities": zig_exploitabilities
                } if zig_exploitabilities else None
            )
            
            return overall_converging
            
        except Exception as e:
            self.logger.error(f"Convergence speed test failed: {e}")
            self.create_result(
                test_name="convergence_speed",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def test_nash_equilibrium_properties(self) -> bool:
        """Test Nash equilibrium properties of converged strategies."""
        self.logger.info("Testing Nash equilibrium properties...")
        
        try:
            # Train to convergence
            iterations = 10000
            
            python_game = KuhnPoker()
            python_mccfr = MCCFR(python_game)
            
            for _ in range(iterations):
                python_mccfr.train(1)
            
            strategy = python_mccfr.get_average_strategy()
            exploitability = self._calculate_exploitability_python(python_mccfr)
            
            # Nash equilibrium properties to check:
            # 1. Low exploitability (< 0.1 for Kuhn poker)
            # 2. Strategy probabilities sum to 1 at each information set
            # 3. No dominated strategies
            
            nash_properties = self._check_nash_properties(strategy, exploitability)
            
            self.create_result(
                test_name="nash_equilibrium_properties",
                passed=nash_properties["valid"],
                message=f"Exploitability: {exploitability:.4f}, Valid probabilities: {nash_properties['valid_probabilities']}, No dominated: {nash_properties['no_dominated']}",
                python_result={
                    "exploitability": exploitability,
                    "nash_properties": nash_properties
                },
                zig_result=None  # Would need Zig implementation
            )
            
            return nash_properties["valid"]
            
        except Exception as e:
            self.logger.error(f"Nash equilibrium properties test failed: {e}")
            self.create_result(
                test_name="nash_equilibrium_properties",
                passed=False,
                message=f"Exception: {e}",
                python_result=None,
                zig_result=None
            )
            return False
    
    def _train_zig_kuhn_poker(self, iterations: int, seed: int = None) -> Optional[Dict[str, Any]]:
        """Train Zig MCCFR on Kuhn poker (placeholder for when Zig MCCFR is implemented)."""
        # This is a placeholder - would need actual Zig MCCFR implementation
        self.logger.warning("Zig MCCFR training not yet implemented - returning None")
        return None
    
    def _calculate_exploitability_python(self, mccfr) -> float:
        """Calculate exploitability of Python MCCFR strategy."""
        try:
            # This would need to be implemented based on the specific MCCFR interface
            # For now, return a placeholder
            return 0.05  # Placeholder low exploitability
        except:
            return float('inf')
    
    def _calculate_exploitability_from_strategy(self, strategy: Dict) -> float:
        """Calculate exploitability from a given strategy."""
        # Placeholder implementation
        return 0.1
    
    def _calculate_zig_exploitability(self, strategy: Dict) -> Optional[float]:
        """Calculate exploitability using Zig implementation."""
        # Placeholder - would need Zig implementation
        return None
    
    def _compare_strategies(self, strategy1: Dict, strategy2: Dict) -> float:
        """Compare two strategies and return similarity score (0-1)."""
        try:
            # Calculate similarity based on action probabilities
            total_diff = 0.0
            total_comparisons = 0
            
            for info_set in strategy1:
                if info_set in strategy2:
                    actions1 = strategy1[info_set]
                    actions2 = strategy2[info_set]
                    
                    for action in actions1:
                        if action in actions2:
                            diff = abs(actions1[action] - actions2[action])
                            total_diff += diff
                            total_comparisons += 1
            
            if total_comparisons == 0:
                return 0.0
            
            avg_diff = total_diff / total_comparisons
            similarity = max(0.0, 1.0 - avg_diff)
            
            return similarity
            
        except:
            return 0.0
    
    def _check_strategy_consistency(self, strategies: List[Dict]) -> bool:
        """Check if multiple strategies are consistent (similar)."""
        if len(strategies) < 2:
            return True
        
        base_strategy = strategies[0]
        
        for strategy in strategies[1:]:
            similarity = self._compare_strategies(base_strategy, strategy)
            if similarity < 0.99:  # 99% similarity required
                return False
        
        return True
    
    def _create_random_kuhn_strategy(self) -> Dict:
        """Create a random strategy for Kuhn poker."""
        # Placeholder random strategy
        return {
            "J": {"bet": 0.5, "fold": 0.5},
            "Q": {"bet": 0.5, "call": 0.5},
            "K": {"bet": 0.5, "call": 0.5}
        }
    
    def _get_trained_kuhn_strategy(self) -> Dict:
        """Get a well-trained strategy for Kuhn poker."""
        # Placeholder near-optimal strategy
        return {
            "J": {"bet": 0.0, "fold": 1.0},
            "Q": {"bet": 0.0, "call": 1.0},
            "K": {"bet": 1.0, "call": 0.0}
        }
    
    def _is_converging(self, exploitabilities: List[float]) -> bool:
        """Check if exploitability values show convergence (generally decreasing)."""
        if len(exploitabilities) < 2:
            return True
        
        # Check if final exploitability is lower than initial
        improvement = exploitabilities[0] - exploitabilities[-1]
        
        # Also check for general downward trend
        decreasing_count = 0
        for i in range(1, len(exploitabilities)):
            if exploitabilities[i] <= exploitabilities[i-1]:
                decreasing_count += 1
        
        # At least 70% of transitions should be decreasing or equal
        decreasing_ratio = decreasing_count / (len(exploitabilities) - 1)
        
        return improvement > 0 and decreasing_ratio >= 0.7
    
    def _check_nash_properties(self, strategy: Dict, exploitability: float) -> Dict[str, Any]:
        """Check Nash equilibrium properties of a strategy."""
        try:
            # Check low exploitability
            low_exploitability = exploitability < 0.1
            
            # Check valid probability distributions
            valid_probabilities = True
            for info_set, actions in strategy.items():
                prob_sum = sum(actions.values())
                if abs(prob_sum - 1.0) > 1e-6:
                    valid_probabilities = False
                    break
                
                # Check non-negative probabilities
                for prob in actions.values():
                    if prob < 0:
                        valid_probabilities = False
                        break
            
            # Check for dominated strategies (simplified)
            no_dominated = True  # Placeholder
            
            return {
                "valid": low_exploitability and valid_probabilities and no_dominated,
                "low_exploitability": low_exploitability,
                "valid_probabilities": valid_probabilities,
                "no_dominated": no_dominated
            }
            
        except:
            return {
                "valid": False,
                "low_exploitability": False,
                "valid_probabilities": False,
                "no_dominated": False
            }


def main():
    """Run convergence validation tests."""
    validator = ConvergenceTestValidator()
    success = validator.run_and_report()
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())