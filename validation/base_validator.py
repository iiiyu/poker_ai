"""
Base validation framework for consistent testing across all validation modules.

This provides a standard interface and common utilities for all validation tests.
"""

import json
import subprocess
import sys
import time
import tempfile
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
import logging


class ValidationResult:
    """Result of a validation test with detailed metadata."""
    
    def __init__(
        self,
        test_name: str,
        passed: bool,
        message: str = "",
        python_result: Any = None,
        zig_result: Any = None,
        metadata: Dict[str, Any] = None
    ):
        self.test_name = test_name
        self.passed = passed
        self.message = message
        self.python_result = python_result
        self.zig_result = zig_result
        self.metadata = metadata or {}
        self.timestamp = time.time()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "test_name": self.test_name,
            "passed": self.passed,
            "message": self.message,
            "python_result": self.python_result,
            "zig_result": self.zig_result,
            "metadata": self.metadata,
            "timestamp": self.timestamp
        }


class BaseValidator(ABC):
    """Base class for all validation modules."""
    
    def __init__(self, project_root: Path = None):
        self.project_root = project_root or Path(__file__).parent.parent
        self.zig_dir = self.project_root / "zig"
        self.zig_clustering_dir = self.project_root / "poker_ai" / "zig_clustering"
        self.validation_dir = self.project_root / "validation"
        self.results: List[ValidationResult] = []
        
        # Setup logging
        self.logger = logging.getLogger(self.__class__.__name__)
        self._setup_logging()
        
        # Check Python availability
        self.python_available = self._check_python_availability()
        
    def _setup_logging(self):
        """Setup logging for validation."""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(sys.stdout),
                logging.FileHandler(self.validation_dir / "validation.log")
            ]
        )
    
    def _check_python_availability(self) -> bool:
        """Check if Python poker_ai module is available."""
        try:
            sys.path.append(str(self.project_root))
            from poker_ai.poker.evaluation.evaluator import Evaluator
            return True
        except ImportError as e:
            self.logger.warning(f"Python poker_ai module not available: {e}")
            return False
    
    def run_zig_command(
        self, 
        args: List[str], 
        cwd: Path = None, 
        timeout: int = 60,
        input_data: str = None
    ) -> subprocess.CompletedProcess:
        """Run a Zig command and return the result."""
        cwd = cwd or self.zig_dir
        
        try:
            result = subprocess.run(
                args,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=timeout,
                input=input_data
            )
            return result
        except subprocess.TimeoutExpired:
            raise TimeoutError(f"Zig command timed out after {timeout}s: {' '.join(args)}")
        except Exception as e:
            raise RuntimeError(f"Failed to run Zig command {' '.join(args)}: {e}")
    
    def create_temp_zig_file(self, content: str, suffix: str = ".zig") -> Path:
        """Create a temporary Zig file with given content."""
        temp_file = tempfile.NamedTemporaryFile(
            mode='w',
            suffix=suffix,
            delete=False,
            dir=self.zig_dir / "temp"
        )
        
        # Ensure temp directory exists
        (self.zig_dir / "temp").mkdir(exist_ok=True)
        
        temp_file.write(content)
        temp_file.close()
        return Path(temp_file.name)
    
    def build_zig_project(self, target: str = None) -> bool:
        """Build the Zig project."""
        build_args = ["zig", "build"]
        if target:
            build_args.append(target)
        
        try:
            result = self.run_zig_command(build_args, timeout=120)
            if result.returncode != 0:
                self.logger.error(f"Zig build failed: {result.stderr}")
                return False
            return True
        except Exception as e:
            self.logger.error(f"Failed to build Zig project: {e}")
            return False
    
    def add_result(self, result: ValidationResult):
        """Add a validation result."""
        self.results.append(result)
        
        status = "✅ PASS" if result.passed else "❌ FAIL"
        self.logger.info(f"{status} {result.test_name}: {result.message}")
    
    def create_result(
        self,
        test_name: str,
        passed: bool,
        message: str = "",
        python_result: Any = None,
        zig_result: Any = None,
        **metadata
    ) -> ValidationResult:
        """Create and add a validation result."""
        result = ValidationResult(
            test_name=test_name,
            passed=passed,
            message=message,
            python_result=python_result,
            zig_result=zig_result,
            metadata=metadata
        )
        self.add_result(result)
        return result
    
    def get_summary(self) -> Dict[str, Any]:
        """Get summary of all validation results."""
        if not self.results:
            return {"total": 0, "passed": 0, "failed": 0, "success_rate": 0.0}
        
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total - passed
        
        return {
            "total": total,
            "passed": passed,
            "failed": failed,
            "success_rate": passed / total,
            "python_available": self.python_available
        }
    
    def save_results(self, filename: str = None) -> Path:
        """Save validation results to JSON file."""
        if filename is None:
            timestamp = int(time.time())
            filename = f"{self.__class__.__name__.lower()}_{timestamp}.json"
        
        results_file = self.validation_dir / filename
        
        report_data = {
            "validator": self.__class__.__name__,
            "timestamp": time.time(),
            "summary": self.get_summary(),
            "results": [r.to_dict() for r in self.results],
            "environment": {
                "python_available": self.python_available,
                "zig_version": self._get_zig_version(),
                "project_root": str(self.project_root)
            }
        }
        
        with open(results_file, 'w') as f:
            json.dump(report_data, f, indent=2, default=str)
        
        self.logger.info(f"Results saved to: {results_file}")
        return results_file
    
    def _get_zig_version(self) -> str:
        """Get Zig version."""
        try:
            result = self.run_zig_command(["zig", "version"], timeout=10)
            return result.stdout.strip() if result.returncode == 0 else "unknown"
        except:
            return "unknown"
    
    @abstractmethod
    def run_tests(self) -> bool:
        """Run all validation tests for this module."""
        pass
    
    @abstractmethod
    def get_test_description(self) -> str:
        """Get description of what this validator tests."""
        pass
    
    def run_and_report(self) -> bool:
        """Run tests and generate a comprehensive report."""
        self.logger.info(f"Starting {self.__class__.__name__}")
        self.logger.info(f"Description: {self.get_test_description()}")
        
        start_time = time.time()
        success = self.run_tests()
        duration = time.time() - start_time
        
        summary = self.get_summary()
        self.logger.info(f"Completed in {duration:.2f}s")
        self.logger.info(f"Results: {summary['passed']}/{summary['total']} passed ({summary['success_rate']:.1%})")
        
        # Save results
        self.save_results()
        
        return success