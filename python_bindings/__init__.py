"""
Python bindings for Zig poker AI library.

This package provides a high-level Python interface to the performance-optimized
Zig poker AI components while maintaining API compatibility with existing
Python interfaces.

Key Features:
- Memory-efficient FFI bindings using ctypes
- Automatic memory management with context managers
- Comprehensive error handling and type safety
- Numpy array support for efficient data transfer
- Strategy format conversion between Python and Zig
- Drop-in replacement for existing Python AI classes
- Both sync and async training interfaces

Example Usage:
    >>> from poker_ai.python_bindings import HandEvaluator, GameState
    >>> evaluator = HandEvaluator()
    >>> cards = [0, 1, 2, 3, 4]  # Example cards
    >>> score = evaluator.evaluate_5(cards)
    
    >>> game = GameState(num_players=4, small_blind=10, big_blind=20)
    >>> game.deal_hole_cards(0, 0, 13)  # Deal cards to player 0
    >>> game.apply_action(1, 20)  # Player action

For training:
    >>> from poker_ai.python_bindings import TrainingConfig, ZigTrainingInterface
    >>> config = TrainingConfig(iterations=1000, num_threads=4)
    >>> trainer = ZigTrainingInterface(config)
    >>> result = trainer.train_sync()

For compatibility with existing code:
    >>> from poker_ai.python_bindings import CompatibilityTrainer
    >>> config = {'iterations': 1000, 'n_jobs': 4, 'verbose': True}
    >>> trainer = CompatibilityTrainer(config)
    >>> result = trainer.train()
"""

from .poker_ai_zig import (
    # Core classes
    HandEvaluator,
    GameState, 
    CFRTrainer,
    StrategyTable,
    
    # Utility functions
    card_from_rank_suit,
    card_get_rank,
    card_get_suit,
    get_version,
    poker_ai_context,
    
    # Exceptions
    PokerAIError,
    InvalidParameterError,
    AllocationError,
    GameStateError,
    StrategyError,
    FileError,
)

from .game_state_converter import (
    # Converter classes
    GameStateConverter,
    NumpyArrayConverter,
    MemoryManager,
    
    # Data classes
    PythonGameState,
    PlayerState,
    
    # Enums
    ActionType,
    GamePhase,
    
    # Utility functions
    get_converter,
    get_memory_manager,
)

from .strategy_loader import (
    # Strategy handling
    StrategyLoader,
    StrategyFormat,
    StrategyCompatibilityChecker,
    
    # Utility functions
    get_strategy_loader,
)

from .training_interface import (
    # Training classes
    TrainingConfig,
    TrainingProgress,
    ZigTrainingInterface,
    BatchTrainingManager,
    CompatibilityTrainer,
    
    # Monitoring
    TrainingMonitor,
    TrainingJob,
)

# Version information
__version__ = "1.0.0"
__author__ = "Poker AI Team"
__license__ = "MIT"

# Package metadata
__all__ = [
    # Core poker AI classes
    "HandEvaluator",
    "GameState", 
    "CFRTrainer",
    "StrategyTable",
    
    # Utility functions
    "card_from_rank_suit",
    "card_get_rank", 
    "card_get_suit",
    "get_version",
    "poker_ai_context",
    
    # Exceptions
    "PokerAIError",
    "InvalidParameterError",
    "AllocationError",
    "GameStateError", 
    "StrategyError",
    "FileError",
    
    # Game state conversion
    "GameStateConverter",
    "NumpyArrayConverter",
    "MemoryManager",
    "PythonGameState",
    "PlayerState",
    "ActionType",
    "GamePhase",
    "get_converter",
    "get_memory_manager",
    
    # Strategy management
    "StrategyLoader",
    "StrategyFormat",
    "StrategyCompatibilityChecker",
    "get_strategy_loader",
    
    # Training interface
    "TrainingConfig",
    "TrainingProgress", 
    "ZigTrainingInterface",
    "BatchTrainingManager",
    "CompatibilityTrainer",
    "TrainingMonitor",
    "TrainingJob",
]

# Convenience imports for backward compatibility
HandEvaluatorZig = HandEvaluator
GameStateZig = GameState
CFRTrainerZig = CFRTrainer

def get_library_info():
    """Get information about the Zig library."""
    version = get_version()
    return {
        'version': f"{version[0]}.{version[1]}.{version[2]}",
        'python_bindings_version': __version__,
        'backend': 'zig',
        'features': [
            'hand_evaluation',
            'game_state_management', 
            'cfr_training',
            'strategy_tables',
            'memory_efficient',
            'multi_threaded'
        ]
    }

def check_compatibility():
    """Check if the Zig library is properly loaded and functional."""
    try:
        # Test basic functionality
        version = get_version()
        evaluator = HandEvaluator()
        
        # Test a simple evaluation
        test_cards = [0, 1, 2, 3, 4]
        result = evaluator.evaluate_5(test_cards)
        
        return {
            'status': 'compatible',
            'version': version,
            'test_result': result,
            'message': 'Zig library is properly loaded and functional'
        }
        
    except Exception as e:
        return {
            'status': 'incompatible',
            'error': str(e),
            'message': 'Zig library failed compatibility check'
        }

# Initialize library on import
try:
    _compatibility_check = check_compatibility()
    if _compatibility_check['status'] != 'compatible':
        import warnings
        warnings.warn(
            f"Zig library compatibility issue: {_compatibility_check['message']}", 
            RuntimeWarning
        )
except Exception as e:
    import warnings
    warnings.warn(
        f"Failed to initialize Zig library: {e}", 
        RuntimeWarning
    )