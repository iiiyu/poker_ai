"""
Master validation runner for comprehensive end-to-end validation.

This script orchestrates all validation modules and provides a unified
interface for running the complete validation suite.
"""

import sys
import json
import time
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional
import subprocess

# Add project root to path
sys.path.append(str(Path(__file__).parent.parent))

from validation.base_validator import BaseValidator
from validation.algorithmic_correctness import AlgorithmicCorrectnessValidator
from validation.convergence_test import ConvergenceTestValidator
from validation.performance_regression import PerformanceRegressionValidator
from validation.memory_profiling import MemoryProfilingValidator
from validation.integration_suite import IntegrationSuiteValidator
from validation.golden_dataset import GoldenDatasetGenerator


class ValidationSuiteRunner:
    """Master validation suite runner."""
    
    def __init__(self, project_root: Path = None):
        self.project_root = project_root or Path(__file__).parent.parent
        self.validation_dir = self.project_root / "validation"
        self.results_dir = self.validation_dir / "results"
        self.results_dir.mkdir(exist_ok=True)
        
        # Initialize validators
        self.validators = {
            "algorithmic_correctness": AlgorithmicCorrectnessValidator(self.project_root),
            "convergence_test": ConvergenceTestValidator(self.project_root),
            "performance_regression": PerformanceRegressionValidator(self.project_root),
            "memory_profiling": MemoryProfilingValidator(self.project_root),
            "integration_suite": IntegrationSuiteValidator(self.project_root),
        }
        
        self.golden_generator = GoldenDatasetGenerator(self.project_root)
        
        # Suite results
        self.suite_results = {
            "start_time": None,
            "end_time": None,
            "duration": None,
            "validator_results": {},
            "overall_passed": False,
            "summary": {}
        }
    
    def run_full_suite(self, validators: List[str] = None, generate_golden: bool = True) -> bool:
        """Run the complete validation suite."""
        print("🚀 Starting Comprehensive Validation Suite")
        print("=" * 60)
        
        self.suite_results["start_time"] = time.time()
        
        validators_to_run = validators or list(self.validators.keys())
        
        # Step 1: Generate golden datasets (if requested)
        if generate_golden:
            print("\n📊 Generating Golden Reference Datasets...")
            print("-" * 40)
            
            golden_success = self.golden_generator.run_and_report()
            if not golden_success:
                print("⚠️  Warning: Golden dataset generation failed - continuing with existing datasets")
        
        # Step 2: Run validation modules
        print("\n🔍 Running Validation Modules...")
        print("-" * 40)
        
        all_passed = True
        
        for validator_name in validators_to_run:
            if validator_name not in self.validators:
                print(f"❌ Unknown validator: {validator_name}")
                continue
            
            print(f"\n▶️  Running {validator_name}...")
            
            validator = self.validators[validator_name]
            
            try:
                start_time = time.time()
                success = validator.run_and_report()
                duration = time.time() - start_time
                
                # Collect results
                summary = validator.get_summary()
                
                self.suite_results["validator_results"][validator_name] = {
                    "success": success,
                    "duration": duration,
                    "summary": summary,
                    "results_file": None  # Will be set by validator.save_results()
                }
                
                if success:
                    print(f"✅ {validator_name}: PASSED ({duration:.1f}s)")
                    print(f"   Results: {summary['passed']}/{summary['total']} tests passed ({summary['success_rate']:.1%})")
                else:
                    print(f"❌ {validator_name}: FAILED ({duration:.1f}s)")
                    print(f"   Results: {summary['passed']}/{summary['total']} tests passed ({summary['success_rate']:.1%})")
                    all_passed = False
                
            except Exception as e:
                print(f"❌ {validator_name}: EXCEPTION - {e}")
                
                self.suite_results["validator_results"][validator_name] = {
                    "success": False,
                    "duration": 0,
                    "summary": {"total": 0, "passed": 0, "failed": 1, "success_rate": 0.0},
                    "error": str(e)
                }
                all_passed = False
        
        # Step 3: Generate comprehensive report
        self.suite_results["end_time"] = time.time()
        self.suite_results["duration"] = self.suite_results["end_time"] - self.suite_results["start_time"]
        self.suite_results["overall_passed"] = all_passed
        
        # Calculate overall summary
        total_tests = sum(r["summary"]["total"] for r in self.suite_results["validator_results"].values())
        passed_tests = sum(r["summary"]["passed"] for r in self.suite_results["validator_results"].values())
        
        self.suite_results["summary"] = {
            "total_validators": len(validators_to_run),
            "passed_validators": sum(1 for r in self.suite_results["validator_results"].values() if r["success"]),
            "total_tests": total_tests,
            "passed_tests": passed_tests,
            "overall_success_rate": passed_tests / total_tests if total_tests > 0 else 0.0
        }
        
        # Save comprehensive report
        self._save_comprehensive_report()
        
        # Print final summary
        self._print_final_summary()
        
        return all_passed
    
    def run_quick_validation(self) -> bool:
        """Run a quick validation with essential tests only."""
        print("⚡ Starting Quick Validation")
        print("=" * 40)
        
        # Run only essential validators
        essential_validators = ["algorithmic_correctness", "performance_regression"]
        
        return self.run_full_suite(
            validators=essential_validators,
            generate_golden=False
        )
    
    def run_ci_validation(self) -> bool:
        """Run validation suitable for CI/CD pipeline."""
        print("🔄 Starting CI/CD Validation")
        print("=" * 40)
        
        # Run all validators except memory profiling (can be flaky in CI)
        ci_validators = [
            "algorithmic_correctness",
            "performance_regression", 
            "integration_suite"
        ]
        
        return self.run_full_suite(
            validators=ci_validators,
            generate_golden=False
        )
    
    def run_nightly_validation(self) -> bool:
        """Run comprehensive nightly validation."""
        print("🌙 Starting Nightly Validation")
        print("=" * 40)
        
        # Run all validators with golden dataset generation
        return self.run_full_suite(
            validators=None,  # All validators
            generate_golden=True
        )
    
    def _save_comprehensive_report(self):
        """Save comprehensive validation report."""
        timestamp = int(time.time())
        report_file = self.results_dir / f"validation_suite_report_{timestamp}.json"
        
        # Add environment information
        env_info = {
            "python_version": sys.version,
            "platform": sys.platform,
            "project_root": str(self.project_root),
            "validation_timestamp": timestamp
        }
        
        comprehensive_report = {
            "environment": env_info,
            "suite_results": self.suite_results,
            "validation_matrix": self._generate_validation_matrix()
        }
        
        with open(report_file, 'w') as f:
            json.dump(comprehensive_report, f, indent=2, default=str)
        
        print(f"\n📋 Comprehensive report saved: {report_file}")
    
    def _generate_validation_matrix(self) -> Dict[str, Any]:
        """Generate validation matrix summary."""
        matrix = {
            "compatibility": {},
            "performance": {},
            "reliability": {}
        }
        
        # Extract key metrics from validator results
        for validator_name, result in self.suite_results["validator_results"].items():
            if not result["success"]:
                continue
            
            summary = result["summary"]
            
            if validator_name == "algorithmic_correctness":
                matrix["compatibility"]["algorithmic"] = {
                    "status": "PASS" if summary["success_rate"] >= 0.99 else "FAIL",
                    "success_rate": summary["success_rate"]
                }
            
            elif validator_name == "performance_regression":
                matrix["performance"]["regression"] = {
                    "status": "PASS" if summary["success_rate"] >= 0.8 else "FAIL",
                    "success_rate": summary["success_rate"]
                }
            
            elif validator_name == "memory_profiling":
                matrix["reliability"]["memory"] = {
                    "status": "PASS" if summary["success_rate"] >= 0.8 else "FAIL",
                    "success_rate": summary["success_rate"]
                }
            
            elif validator_name == "integration_suite":
                matrix["reliability"]["integration"] = {
                    "status": "PASS" if summary["success_rate"] >= 0.7 else "FAIL",
                    "success_rate": summary["success_rate"]
                }
        
        return matrix
    
    def _print_final_summary(self):
        """Print final validation summary."""
        print("\n" + "=" * 60)
        print("📊 VALIDATION SUITE SUMMARY")
        print("=" * 60)
        
        duration_min = self.suite_results["duration"] / 60
        
        print(f"Duration: {duration_min:.1f} minutes")
        print(f"Overall Status: {'✅ PASSED' if self.suite_results['overall_passed'] else '❌ FAILED'}")
        
        summary = self.suite_results["summary"]
        print(f"\nValidators: {summary['passed_validators']}/{summary['total_validators']} passed")
        print(f"Total Tests: {summary['passed_tests']}/{summary['total_tests']} passed ({summary['overall_success_rate']:.1%})")
        
        print("\nValidator Results:")
        for validator_name, result in self.suite_results["validator_results"].items():
            status = "✅ PASS" if result["success"] else "❌ FAIL"
            duration = result["duration"]
            tests = result["summary"]
            print(f"  {status} {validator_name:25} ({duration:5.1f}s) - {tests['passed']}/{tests['total']} tests")
        
        if self.suite_results["overall_passed"]:
            print("\n🎉 ALL VALIDATIONS PASSED!")
            print("The Zig implementation is ready for production use.")
        else:
            print("\n⚠️  VALIDATION FAILURES DETECTED")
            print("Review failed tests before deployment.")
        
        print("=" * 60)


def main():
    """Main entry point for validation suite."""
    parser = argparse.ArgumentParser(
        description="Comprehensive validation suite for Zig-Python poker AI compatibility"
    )
    
    parser.add_argument(
        "--mode",
        choices=["full", "quick", "ci", "nightly"],
        default="full",
        help="Validation mode to run"
    )
    
    parser.add_argument(
        "--validators",
        nargs="+",
        choices=[
            "algorithmic_correctness",
            "convergence_test", 
            "performance_regression",
            "memory_profiling",
            "integration_suite"
        ],
        help="Specific validators to run (overrides mode)"
    )
    
    parser.add_argument(
        "--no-golden",
        action="store_true",
        help="Skip golden dataset generation"
    )
    
    parser.add_argument(
        "--project-root",
        type=str,
        help="Project root directory"
    )
    
    args = parser.parse_args()
    
    # Initialize runner
    project_root = Path(args.project_root) if args.project_root else None
    runner = ValidationSuiteRunner(project_root)
    
    # Run validation based on mode
    try:
        if args.validators:
            # Custom validator selection
            success = runner.run_full_suite(
                validators=args.validators,
                generate_golden=not args.no_golden
            )
        elif args.mode == "quick":
            success = runner.run_quick_validation()
        elif args.mode == "ci":
            success = runner.run_ci_validation()
        elif args.mode == "nightly":
            success = runner.run_nightly_validation()
        else:  # full
            success = runner.run_full_suite(
                generate_golden=not args.no_golden
            )
        
        return 0 if success else 1
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Validation interrupted by user")
        return 1
    except Exception as e:
        print(f"\n\n❌ Validation suite failed with exception: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())