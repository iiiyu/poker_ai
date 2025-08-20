"""
Strategy loading and serialization utilities.

Handles loading, saving, and converting poker AI strategies between
Python formats (joblib, pickle) and Zig formats, maintaining
compatibility with existing strategy files.
"""

import os
import pickle
import gzip
import json
from typing import Dict, Any, Optional, Union, List
from pathlib import Path
import numpy as np
import tempfile
import shutil

try:
    import joblib
    HAS_JOBLIB = True
except ImportError:
    HAS_JOBLIB = False

from .poker_ai_zig import StrategyTable, FileError
from .game_state_converter import get_converter

class StrategyFormat:
    """Strategy file format constants."""
    JOBLIB = "joblib"
    PICKLE = "pickle"
    GZIP_PICKLE = "gzip_pickle"
    JSON = "json"
    ZIG_BINARY = "zig_binary"

class StrategyLoader:
    """Loads and converts poker AI strategies between formats."""
    
    def __init__(self):
        self.converter = get_converter()
        self._temp_files = []
    
    def __del__(self):
        """Cleanup temporary files."""
        for temp_file in self._temp_files:
            try:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
            except OSError:
                pass
    
    def detect_format(self, file_path: str) -> str:
        """Detect the format of a strategy file."""
        path = Path(file_path)
        
        if not path.exists():
            raise FileNotFoundError(f"Strategy file not found: {file_path}")
        
        # Check by extension first
        suffix = path.suffix.lower()
        if suffix == '.joblib':
            return StrategyFormat.JOBLIB
        elif suffix == '.json':
            return StrategyFormat.JSON
        elif suffix == '.gz':
            return StrategyFormat.GZIP_PICKLE
        elif suffix == '.pkl' or suffix == '.pickle':
            return StrategyFormat.PICKLE
        elif suffix == '.zig':
            return StrategyFormat.ZIG_BINARY
        
        # Try to detect by content
        try:
            with open(file_path, 'rb') as f:
                header = f.read(16)
            
            # JSON files start with '{' or '['
            if header.startswith(b'{') or header.startswith(b'['):
                return StrategyFormat.JSON
            
            # Gzip files have magic number
            if header.startswith(b'\x1f\x8b'):
                return StrategyFormat.GZIP_PICKLE
            
            # Pickle files have specific magic numbers
            if header.startswith(b'\x80\x03') or header.startswith(b'\x80\x04'):
                return StrategyFormat.PICKLE
            
            # Try joblib detection
            if HAS_JOBLIB:
                try:
                    joblib.load(file_path)
                    return StrategyFormat.JOBLIB
                except:
                    pass
            
            # Default to Zig binary if nothing else matches
            return StrategyFormat.ZIG_BINARY
            
        except Exception:
            raise ValueError(f"Cannot detect format of file: {file_path}")
    
    def load_python_strategy(self, file_path: str, format: Optional[str] = None) -> Dict[str, Any]:
        """Load strategy from Python format (joblib, pickle, etc.)."""
        if format is None:
            format = self.detect_format(file_path)
        
        if format == StrategyFormat.JOBLIB:
            if not HAS_JOBLIB:
                raise ImportError("joblib not available for loading strategy")
            return joblib.load(file_path)
        
        elif format == StrategyFormat.PICKLE:
            with open(file_path, 'rb') as f:
                return pickle.load(f)
        
        elif format == StrategyFormat.GZIP_PICKLE:
            with gzip.open(file_path, 'rb') as f:
                return pickle.load(f)
        
        elif format == StrategyFormat.JSON:
            with open(file_path, 'r') as f:
                return json.load(f)
        
        else:
            raise ValueError(f"Unsupported Python format: {format}")
    
    def save_python_strategy(self, strategy: Dict[str, Any], file_path: str, 
                           format: str = StrategyFormat.JOBLIB) -> None:
        """Save strategy to Python format."""
        if format == StrategyFormat.JOBLIB:
            if not HAS_JOBLIB:
                raise ImportError("joblib not available for saving strategy")
            joblib.dump(strategy, file_path)
        
        elif format == StrategyFormat.PICKLE:
            with open(file_path, 'wb') as f:
                pickle.dump(strategy, f)
        
        elif format == StrategyFormat.GZIP_PICKLE:
            with gzip.open(file_path, 'wb') as f:
                pickle.dump(strategy, f)
        
        elif format == StrategyFormat.JSON:
            # Convert numpy arrays to lists for JSON serialization
            json_strategy = self._convert_for_json(strategy)
            with open(file_path, 'w') as f:
                json.dump(json_strategy, f, indent=2)
        
        else:
            raise ValueError(f"Unsupported Python format: {format}")
    
    def load_zig_strategy(self, file_path: str) -> StrategyTable:
        """Load strategy directly into Zig StrategyTable."""
        strategy_table = StrategyTable()
        strategy_table.load(file_path)
        return strategy_table
    
    def save_zig_strategy(self, strategy_table: StrategyTable, file_path: str) -> None:
        """Save Zig StrategyTable to file."""
        strategy_table.save(file_path)
    
    def convert_python_to_zig(self, python_strategy: Dict[str, Any], 
                            zig_file_path: str) -> None:
        """Convert Python strategy to Zig format."""
        # Create temporary JSON file for intermediate representation
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as temp_file:
            temp_path = temp_file.name
            self._temp_files.append(temp_path)
            
            # Convert to JSON-serializable format
            json_strategy = self._convert_for_json(python_strategy)
            json.dump(json_strategy, temp_file, indent=2)
        
        # Load into Zig and save in Zig format
        try:
            # Create a new strategy table and populate it
            strategy_table = StrategyTable()
            
            # Load the JSON data and convert to Zig-compatible format
            self._populate_zig_strategy(strategy_table, json_strategy)
            
            # Save in Zig binary format
            strategy_table.save(zig_file_path)
            
        finally:
            # Cleanup temp file
            if os.path.exists(temp_path):
                os.unlink(temp_path)
                self._temp_files.remove(temp_path)
    
    def convert_zig_to_python(self, zig_file_path: str, 
                            python_file_path: str,
                            python_format: str = StrategyFormat.JOBLIB) -> Dict[str, Any]:
        """Convert Zig strategy to Python format."""
        # Load from Zig
        strategy_table = self.load_zig_strategy(zig_file_path)
        
        # Extract strategy data
        python_strategy = self._extract_python_strategy(strategy_table)
        
        # Save in Python format
        self.save_python_strategy(python_strategy, python_file_path, python_format)
        
        return python_strategy
    
    def _convert_for_json(self, obj: Any) -> Any:
        """Convert objects to JSON-serializable format."""
        if isinstance(obj, np.ndarray):
            return {
                '__numpy_array__': True,
                'dtype': str(obj.dtype),
                'shape': obj.shape,
                'data': obj.tolist()
            }
        elif isinstance(obj, np.integer):
            return int(obj)
        elif isinstance(obj, np.floating):
            return float(obj)
        elif isinstance(obj, dict):
            return {key: self._convert_for_json(value) for key, value in obj.items()}
        elif isinstance(obj, (list, tuple)):
            return [self._convert_for_json(item) for item in obj]
        else:
            return obj
    
    def _restore_from_json(self, obj: Any) -> Any:
        """Restore objects from JSON format."""
        if isinstance(obj, dict):
            if obj.get('__numpy_array__'):
                dtype = np.dtype(obj['dtype'])
                data = np.array(obj['data'], dtype=dtype)
                return data.reshape(obj['shape'])
            else:
                return {key: self._restore_from_json(value) for key, value in obj.items()}
        elif isinstance(obj, list):
            return [self._restore_from_json(item) for item in obj]
        else:
            return obj
    
    def _populate_zig_strategy(self, strategy_table: StrategyTable, strategy_data: Dict[str, Any]) -> None:
        """Populate Zig strategy table with Python strategy data."""
        # This is a placeholder implementation
        # In a real implementation, you would need to call specific Zig functions
        # to populate the strategy table with the converted data
        
        # For now, we'll create a temporary file and use the Zig loader
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as temp_file:
            temp_path = temp_file.name
            self._temp_files.append(temp_path)
            json.dump(strategy_data, temp_file)
        
        # Note: This would require additional Zig C API functions to load from JSON
        # For now, this is a placeholder that shows the intended flow
        pass
    
    def _extract_python_strategy(self, strategy_table: StrategyTable) -> Dict[str, Any]:
        """Extract strategy data from Zig strategy table."""
        # This is a placeholder implementation
        # In a real implementation, you would need to call specific Zig functions
        # to extract data from the strategy table
        
        return {
            'memory_usage': strategy_table.memory_usage,
            'format_version': '1.0',
            'extracted_from_zig': True,
            # Additional strategy data would be extracted here
        }

class StrategyCompatibilityChecker:
    """Checks compatibility between different strategy formats."""
    
    def __init__(self):
        self.loader = StrategyLoader()
    
    def check_compatibility(self, file1: str, file2: str) -> Dict[str, Any]:
        """Check compatibility between two strategy files."""
        try:
            # Load both strategies
            format1 = self.loader.detect_format(file1)
            format2 = self.loader.detect_format(file2)
            
            if format1 in [StrategyFormat.ZIG_BINARY]:
                strategy1 = self.loader.load_zig_strategy(file1)
                strategy1_data = self.loader._extract_python_strategy(strategy1)
            else:
                strategy1_data = self.loader.load_python_strategy(file1, format1)
            
            if format2 in [StrategyFormat.ZIG_BINARY]:
                strategy2 = self.loader.load_zig_strategy(file2)
                strategy2_data = self.loader._extract_python_strategy(strategy2)
            else:
                strategy2_data = self.loader.load_python_strategy(file2, format2)
            
            # Compare strategies
            compatibility_score = self._compute_compatibility(strategy1_data, strategy2_data)
            
            return {
                'file1': file1,
                'file2': file2,
                'format1': format1,
                'format2': format2,
                'compatibility_score': compatibility_score,
                'is_compatible': compatibility_score > 0.95,
                'differences': self._find_differences(strategy1_data, strategy2_data)
            }
            
        except Exception as e:
            return {
                'file1': file1,
                'file2': file2,
                'error': str(e),
                'is_compatible': False
            }
    
    def _compute_compatibility(self, strategy1: Dict[str, Any], strategy2: Dict[str, Any]) -> float:
        """Compute compatibility score between strategies."""
        # Simplified compatibility check
        # In a real implementation, this would compare strategy tables,
        # action probabilities, etc.
        
        common_keys = set(strategy1.keys()) & set(strategy2.keys())
        total_keys = set(strategy1.keys()) | set(strategy2.keys())
        
        if not total_keys:
            return 1.0
        
        key_overlap = len(common_keys) / len(total_keys)
        
        # Compare values for common keys
        value_similarity = 0.0
        for key in common_keys:
            val1, val2 = strategy1[key], strategy2[key]
            if isinstance(val1, (int, float)) and isinstance(val2, (int, float)):
                if val1 == val2:
                    value_similarity += 1.0
                elif val1 != 0 or val2 != 0:
                    value_similarity += 1.0 - abs(val1 - val2) / (abs(val1) + abs(val2))
            elif val1 == val2:
                value_similarity += 1.0
        
        if common_keys:
            value_similarity /= len(common_keys)
        
        return (key_overlap + value_similarity) / 2.0
    
    def _find_differences(self, strategy1: Dict[str, Any], strategy2: Dict[str, Any]) -> List[str]:
        """Find differences between strategies."""
        differences = []
        
        keys1, keys2 = set(strategy1.keys()), set(strategy2.keys())
        
        if keys1 - keys2:
            differences.append(f"Keys only in first strategy: {keys1 - keys2}")
        
        if keys2 - keys1:
            differences.append(f"Keys only in second strategy: {keys2 - keys1}")
        
        for key in keys1 & keys2:
            val1, val2 = strategy1[key], strategy2[key]
            if val1 != val2:
                differences.append(f"Different values for '{key}': {val1} vs {val2}")
        
        return differences

# Global instance
_strategy_loader = None

def get_strategy_loader() -> StrategyLoader:
    """Get the global strategy loader instance."""
    global _strategy_loader
    if _strategy_loader is None:
        _strategy_loader = StrategyLoader()
    return _strategy_loader