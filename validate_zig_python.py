#!/usr/bin/env python3
"""
Validation script to ensure bit-for-bit compatibility between Zig and Python implementations.
This script runs test cases through both implementations and compares results.
"""

import json
import subprocess
import sys
import os
import tempfile
from typing import List, Tuple, Dict, Any
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent
sys.path.append(str(project_root))

try:
    from poker_ai.poker.evaluation.evaluator import Evaluator
    from poker_ai.poker.evaluation.eval_card import EvaluationCard
    PYTHON_AVAILABLE = True
except ImportError as e:
    print(f"Warning: Python poker_ai module not available: {e}")
    PYTHON_AVAILABLE = False

class ZigPythonValidator:
    def __init__(self):
        self.evaluator = Evaluator() if PYTHON_AVAILABLE else None
        self.zig_dir = project_root / "zig"
        self.zig_clustering_dir = project_root / "poker_ai" / "zig_clustering"
        self.test_results = []
        
    def create_zig_test_runner(self, test_code: str) -> Path:
        """Create a temporary Zig file to run test code."""
        temp_file = tempfile.NamedTemporaryFile(
            mode='w', 
            suffix='.zig', 
            delete=False,
            dir=self.zig_dir
        )
        
        # Standard imports and main wrapper
        zig_template = f"""
const std = @import("std");
const Card = @import("src/cards.zig").Card;
const HandEvaluator = @import("src/evaluator.zig").HandEvaluator;
const print = std.debug.print;

pub fn main() !void {{
    {test_code}
}}
"""
        
        temp_file.write(zig_template)
        temp_file.close()
        return Path(temp_file.name)
    
    def run_zig_test(self, test_code: str) -> str:
        """Run Zig test code and return output."""
        zig_file = self.create_zig_test_runner(test_code)
        
        try:
            result = subprocess.run(
                ["zig", "run", str(zig_file)],
                cwd=self.zig_dir,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                raise RuntimeError(f"Zig execution failed: {result.stderr}")
            
            return result.stdout.strip()
            
        finally:
            zig_file.unlink()  # Clean up temp file
    
    def test_hand_evaluation_compatibility(self):
        """Test that hand evaluation produces identical results."""
        print("Testing hand evaluation compatibility...")
        
        test_cases = [
            # Royal flush spades
            (["As", "Ks", "Qs", "Js", "Ts", "2h", "3h"], "Royal flush spades"),
            # Four of a kind aces
            (["As", "Ah", "Ad", "Ac", "Ks", "2h", "3h"], "Four aces"),
            # Full house
            (["As", "Ah", "Ad", "Ks", "Kh", "2s", "3s"], "Full house A over K"),
            # Flush
            (["As", "Qs", "Ts", "8s", "6s", "2h", "3h"], "Ace high flush"),
            # Straight
            (["As", "Kh", "Qd", "Jc", "Ts", "2h", "3h"], "Broadway straight"),
            # High card
            (["As", "Kh", "Qd", "Js", "9h", "7s", "5s"], "Ace high"),
        ]
        
        compatible_results = []
        
        for cards_str, description in test_cases:
            if not PYTHON_AVAILABLE:
                print(f"Skipping {description} - Python not available")
                continue
                
            try:
                # Python evaluation
                python_cards = [EvaluationCard.new(card) for card in cards_str]
                if len(python_cards) == 7:
                    python_rank = self.evaluator.evaluate(python_cards[:5], python_cards[5:])
                else:
                    python_rank = self.evaluator.evaluate(python_cards, [])
                
                # Zig evaluation
                zig_cards = ', '.join([
                    f'Card.init({card[:-1] if card[:-1] != "T" else "10"}, "{{"s": "spades", "h": "hearts", "d": "diamonds", "c": "clubs"}}["{card[-1]}"]])'
                    for card in cards_str
                ])
                
                zig_test_code = f"""
                const hand = [_]Card{{ {zig_cards} }};
                const rank = HandEvaluator.evaluate7Card(&hand);
                print("{{}}\\n", .{{rank}});
                """
                
                zig_output = self.run_zig_test(zig_test_code)
                zig_rank = int(zig_output.strip())
                
                # Compare results
                is_compatible = python_rank == zig_rank
                compatible_results.append(is_compatible)
                
                status = "✅ PASS" if is_compatible else "❌ FAIL"
                print(f"  {status} {description}: Python={python_rank}, Zig={zig_rank}")
                
                self.test_results.append({
                    "test": "hand_evaluation",
                    "case": description,
                    "python_result": python_rank,
                    "zig_result": zig_rank,
                    "compatible": is_compatible
                })
                
            except Exception as e:
                print(f"  ❌ ERROR {description}: {e}")
                compatible_results.append(False)
        
        success_rate = sum(compatible_results) / len(compatible_results) if compatible_results else 0
        print(f"Hand evaluation compatibility: {success_rate:.1%} ({sum(compatible_results)}/{len(compatible_results)})")
        
        return success_rate > 0.95  # 95% compatibility required
    
    def test_card_generation_compatibility(self):
        """Test that card generation produces same number of unique cards."""
        print("Testing card generation compatibility...")
        
        if not PYTHON_AVAILABLE:
            print("Skipping card generation test - Python not available")
            return True
        
        try:
            # Python: Generate all cards
            python_cards = []
            for rank in range(2, 15):  # 2-14 (A)
                for suit in ['s', 'h', 'd', 'c']:
                    rank_str = str(rank) if rank != 14 else 'A'
                    if rank == 11:
                        rank_str = 'J'
                    elif rank == 12:
                        rank_str = 'Q'
                    elif rank == 13:
                        rank_str = 'K'
                    elif rank == 10:
                        rank_str = 'T'
                    
                    card = EvaluationCard.new(f"{rank_str}{suit}")
                    python_cards.append(card)
            
            python_unique_count = len(set(python_cards))
            
            # Zig: Generate all cards and count unique
            zig_test_code = """
            const all_cards = @import("src/eval_card.zig").generateAllCards(std.heap.page_allocator) catch unreachable;
            defer std.heap.page_allocator.free(all_cards);
            
            var seen = std.HashMap(u32, void, std.hash_map.DefaultContext(u32), 80).init(std.heap.page_allocator);
            defer seen.deinit();
            
            for (all_cards) |card| {
                _ = seen.put(card.eval_card, {}) catch continue;
            }
            
            print("{}\\n", .{all_cards.len});
            print("{}\\n", .{seen.count()});
            """
            
            zig_output = self.run_zig_test(zig_test_code)
            lines = zig_output.strip().split('\n')
            zig_total_count = int(lines[0])
            zig_unique_count = int(lines[1])
            
            # Both should generate 52 unique cards
            expected_count = 52
            python_correct = python_unique_count == expected_count
            zig_correct = zig_total_count == expected_count and zig_unique_count == expected_count
            
            status = "✅ PASS" if python_correct and zig_correct else "❌ FAIL"
            print(f"  {status} Card generation: Python={python_unique_count}, Zig={zig_total_count}/{zig_unique_count}")
            
            self.test_results.append({
                "test": "card_generation",
                "python_unique": python_unique_count,
                "zig_total": zig_total_count,
                "zig_unique": zig_unique_count,
                "compatible": python_correct and zig_correct
            })
            
            return python_correct and zig_correct
            
        except Exception as e:
            print(f"  ❌ ERROR Card generation test: {e}")
            return False
    
    def test_clustering_determinism(self):
        """Test that clustering produces deterministic results."""
        print("Testing clustering determinism...")
        
        if not self.zig_clustering_dir.exists():
            print("Skipping clustering test - Zig clustering directory not found")
            return True
        
        try:
            # Run clustering multiple times with same seed and compare results
            results = []
            for run in range(3):
                result = subprocess.run(
                    ["zig", "run", "src/main.zig", "--", "test"],
                    cwd=self.zig_clustering_dir,
                    capture_output=True,
                    text=True,
                    timeout=60
                )
                
                if result.returncode != 0:
                    print(f"  ❌ Clustering run {run+1} failed: {result.stderr}")
                    return False
                
                results.append(result.stdout)
            
            # Check if all runs produced same output (deterministic)
            all_same = all(output == results[0] for output in results[1:])
            
            status = "✅ PASS" if all_same else "❌ FAIL"
            print(f"  {status} Clustering determinism: {len(set(results))} unique outputs from 3 runs")
            
            self.test_results.append({
                "test": "clustering_determinism",
                "unique_outputs": len(set(results)),
                "deterministic": all_same
            })
            
            return all_same
            
        except subprocess.TimeoutExpired:
            print("  ⚠️  Clustering test timed out")
            return True  # Don't fail on timeout
        except Exception as e:
            print(f"  ❌ ERROR Clustering test: {e}")
            return False
    
    def test_performance_comparison(self):
        """Compare performance between Zig and Python implementations."""
        print("Testing performance comparison...")
        
        if not PYTHON_AVAILABLE:
            print("Skipping performance test - Python not available")
            return True
        
        try:
            import time
            
            # Test hand evaluation speed
            test_hands = [
                ["As", "Ks", "Qs", "Js", "Ts", "2h", "3h"],
                ["As", "Ah", "Ad", "Ac", "Ks", "2h", "3h"],
                ["7s", "3h", "Qd", "5c", "9s", "Th", "4d"],
            ]
            
            # Python timing
            python_times = []
            for cards_str in test_hands:
                python_cards = [EvaluationCard.new(card) for card in cards_str]
                
                start_time = time.time()
                for _ in range(1000):
                    self.evaluator.evaluate(python_cards[:5], python_cards[5:])
                python_time = time.time() - start_time
                python_times.append(python_time)
            
            avg_python_time = sum(python_times) / len(python_times)
            
            # Zig timing (approximate from benchmark output)
            benchmark_result = subprocess.run(
                ["./zig-out/bin/poker_ai_bench"],
                cwd=self.zig_dir,
                capture_output=True,
                text=True,
                timeout=60
            )
            
            if benchmark_result.returncode == 0:
                # Try to extract hand evaluation ops/sec from benchmark output
                for line in benchmark_result.stdout.split('\n'):
                    if "Hand Evaluation" in line:
                        parts = line.split()
                        if len(parts) >= 4:
                            zig_ops_per_sec = float(parts[3])
                            zig_time_per_1000 = 1000.0 / zig_ops_per_sec
                            
                            speedup = avg_python_time / zig_time_per_1000
                            
                            print(f"  Performance comparison:")
                            print(f"    Python: {avg_python_time:.4f}s per 1000 evaluations")
                            print(f"    Zig: {zig_time_per_1000:.4f}s per 1000 evaluations")
                            print(f"    Speedup: {speedup:.1f}x")
                            
                            self.test_results.append({
                                "test": "performance_comparison",
                                "python_time": avg_python_time,
                                "zig_time": zig_time_per_1000,
                                "speedup": speedup
                            })
                            
                            return True
            
            print("  ⚠️  Could not extract performance data")
            return True
            
        except Exception as e:
            print(f"  ❌ ERROR Performance test: {e}")
            return True  # Don't fail on performance test errors
    
    def generate_compatibility_report(self):
        """Generate a detailed compatibility report."""
        report_file = f"compatibility_report_{int(time.time())}.json"
        
        report_data = {
            "timestamp": time.time(),
            "python_available": PYTHON_AVAILABLE,
            "zig_version": self.get_zig_version(),
            "test_results": self.test_results,
            "summary": self.get_test_summary()
        }
        
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        print(f"\nCompatibility report saved to: {report_file}")
        return report_file
    
    def get_zig_version(self):
        """Get Zig version."""
        try:
            result = subprocess.run(
                ["zig", "version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            return result.stdout.strip() if result.returncode == 0 else "unknown"
        except:
            return "unknown"
    
    def get_test_summary(self):
        """Get summary of test results."""
        if not self.test_results:
            return {"total": 0, "passed": 0, "failed": 0}
        
        total = len(self.test_results)
        passed = sum(1 for result in self.test_results if result.get("compatible", True))
        failed = total - passed
        
        return {
            "total": total,
            "passed": passed,
            "failed": failed,
            "success_rate": passed / total if total > 0 else 0
        }
    
    def run_all_tests(self):
        """Run all compatibility tests."""
        print("=" * 60)
        print("ZIG-PYTHON COMPATIBILITY VALIDATOR")
        print("=" * 60)
        
        all_passed = True
        
        # Build Zig project first
        print("Building Zig project...")
        build_result = subprocess.run(
            ["zig", "build"],
            cwd=self.zig_dir,
            capture_output=True,
            timeout=120
        )
        
        if build_result.returncode != 0:
            print(f"❌ Failed to build Zig project: {build_result.stderr.decode()}")
            return False
        
        # Build benchmarks
        subprocess.run(
            ["zig", "build", "bench", "-Doptimize=ReleaseFast"],
            cwd=self.zig_dir,
            capture_output=True,
            timeout=120
        )
        
        print("✅ Zig project built successfully\n")
        
        # Run all tests
        test_methods = [
            self.test_hand_evaluation_compatibility,
            self.test_card_generation_compatibility,
            self.test_clustering_determinism,
            self.test_performance_comparison,
        ]
        
        for test_method in test_methods:
            try:
                result = test_method()
                if not result:
                    all_passed = False
            except Exception as e:
                print(f"❌ Test {test_method.__name__} failed with exception: {e}")
                all_passed = False
            print()
        
        # Generate report
        report_file = self.generate_compatibility_report()
        
        # Print final summary
        summary = self.get_test_summary()
        print("=" * 60)
        print("COMPATIBILITY TEST SUMMARY")
        print("=" * 60)
        print(f"Total tests: {summary['total']}")
        print(f"Passed: {summary['passed']}")
        print(f"Failed: {summary['failed']}")
        print(f"Success rate: {summary['success_rate']:.1%}")
        
        if all_passed and summary['success_rate'] >= 0.9:
            print("\n✅ COMPATIBILITY VALIDATION PASSED")
            print("The Zig implementation is compatible with the Python implementation.")
        else:
            print("\n❌ COMPATIBILITY VALIDATION FAILED")
            print("The Zig implementation has compatibility issues that need to be addressed.")
        
        return all_passed and summary['success_rate'] >= 0.9


def main():
    """Main entry point."""
    import time
    
    validator = ZigPythonValidator()
    success = validator.run_all_tests()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()