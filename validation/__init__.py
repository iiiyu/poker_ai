"""
Comprehensive validation framework for Zig-Python poker AI compatibility.

This module provides end-to-end validation to ensure 100% functional parity
between the Zig and Python implementations of the poker AI system.
"""

__version__ = "1.0.0"
__author__ = "Poker AI Validation Team"

from .base_validator import BaseValidator
from .test_data_generator import TestDataGenerator
from .golden_dataset import GoldenDataset

__all__ = [
    "BaseValidator",
    "TestDataGenerator", 
    "GoldenDataset",
]