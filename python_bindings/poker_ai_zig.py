"""
Main Python wrapper for Zig poker AI library.

Provides high-level Python interface to the performance-optimized Zig
poker AI components while maintaining API compatibility with existing
Python classes.
"""

import ctypes
import os
import threading
from typing import Optional, List, Tuple, Union
from contextlib import contextmanager
from pathlib import Path
import numpy as np

# Error handling
class PokerAIError(Exception):
    """Base exception for poker AI errors."""
    pass

class InvalidParameterError(PokerAIError):
    """Invalid parameter passed to Zig library."""
    pass

class AllocationError(PokerAIError):
    """Memory allocation failed in Zig library."""
    pass

class GameStateError(PokerAIError):
    """Game state operation failed."""
    pass

class StrategyError(PokerAIError):
    """Strategy operation failed."""
    pass

class FileError(PokerAIError):
    """File operation failed."""
    pass

# Error code mapping
ERROR_MAP = {
    0: None,  # SUCCESS
    -1: InvalidParameterError,
    -2: AllocationError,
    -3: GameStateError,
    -4: StrategyError,
    -5: FileError,
}

def _check_error(error_code: int) -> None:
    """Check Zig error code and raise appropriate Python exception."""
    if error_code != 0:
        error_class = ERROR_MAP.get(error_code, PokerAIError)
        raise error_class(f"Zig library error: {error_code}")

class ZigLibrary:
    """Singleton wrapper for the Zig shared library."""
    
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if not self._initialized:
            self._load_library()
            self._setup_functions()
            self._initialize()
            self._initialized = True
    
    def _load_library(self) -> None:
        """Load the Zig shared library."""
        # Find the shared library
        base_dir = Path(__file__).parent.parent
        zig_lib_dir = base_dir / "zig" / "zig-out" / "lib"
        
        # Platform-specific library names
        if os.name == "nt":
            lib_name = "poker_ai.dll"
        elif os.uname().sysname == "Darwin":
            lib_name = "libpoker_ai.dylib"
        else:
            lib_name = "libpoker_ai.so"
        
        lib_path = zig_lib_dir / lib_name
        
        if not lib_path.exists():
            raise FileNotFoundError(
                f"Zig library not found at {lib_path}. "
                f"Please build with: cd {base_dir}/zig && zig build"
            )
        
        self.lib = ctypes.CDLL(str(lib_path))
    
    def _setup_functions(self) -> None:
        """Setup function signatures for the C API."""
        # Library initialization
        self.lib.poker_ai_init.restype = ctypes.c_int
        self.lib.poker_ai_init.argtypes = []
        
        self.lib.poker_ai_cleanup.restype = None
        self.lib.poker_ai_cleanup.argtypes = []
        
        # Hand evaluator functions
        self.lib.poker_hand_evaluator_create.restype = ctypes.c_uint32
        self.lib.poker_hand_evaluator_create.argtypes = []
        
        self.lib.poker_hand_evaluator_destroy.restype = ctypes.c_int
        self.lib.poker_hand_evaluator_destroy.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_hand_evaluate_5.restype = ctypes.c_uint32
        self.lib.poker_hand_evaluate_5.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8)]
        
        self.lib.poker_hand_evaluate_7.restype = ctypes.c_uint32
        self.lib.poker_hand_evaluate_7.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8)]
        
        # Game state functions
        self.lib.poker_game_state_create.restype = ctypes.c_uint32
        self.lib.poker_game_state_create.argtypes = [ctypes.c_uint8, ctypes.c_uint32, ctypes.c_uint32]
        
        self.lib.poker_game_state_destroy.restype = ctypes.c_int
        self.lib.poker_game_state_destroy.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_game_state_deal_hole_cards.restype = ctypes.c_int
        self.lib.poker_game_state_deal_hole_cards.argtypes = [
            ctypes.c_uint32, ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint8
        ]
        
        self.lib.poker_game_state_apply_action.restype = ctypes.c_int
        self.lib.poker_game_state_apply_action.argtypes = [
            ctypes.c_uint32, ctypes.c_uint8, ctypes.c_uint32
        ]
        
        self.lib.poker_game_state_is_terminal.restype = ctypes.c_int
        self.lib.poker_game_state_is_terminal.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_game_state_get_pot.restype = ctypes.c_uint32
        self.lib.poker_game_state_get_pot.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_game_state_get_current_player.restype = ctypes.c_uint8
        self.lib.poker_game_state_get_current_player.argtypes = [ctypes.c_uint32]
        
        # CFR trainer functions
        self.lib.poker_cfr_trainer_create.restype = ctypes.c_uint32
        self.lib.poker_cfr_trainer_create.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
        
        self.lib.poker_cfr_trainer_destroy.restype = ctypes.c_int
        self.lib.poker_cfr_trainer_destroy.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_cfr_trainer_train.restype = ctypes.c_int
        self.lib.poker_cfr_trainer_train.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_cfr_trainer_save_strategy.restype = ctypes.c_int
        self.lib.poker_cfr_trainer_save_strategy.argtypes = [ctypes.c_uint32, ctypes.c_char_p]
        
        self.lib.poker_cfr_trainer_load_strategy.restype = ctypes.c_int
        self.lib.poker_cfr_trainer_load_strategy.argtypes = [ctypes.c_uint32, ctypes.c_char_p]
        
        # Strategy table functions
        self.lib.poker_strategy_table_create.restype = ctypes.c_uint32
        self.lib.poker_strategy_table_create.argtypes = []
        
        self.lib.poker_strategy_table_destroy.restype = ctypes.c_int
        self.lib.poker_strategy_table_destroy.argtypes = [ctypes.c_uint32]
        
        self.lib.poker_strategy_table_save.restype = ctypes.c_int
        self.lib.poker_strategy_table_save.argtypes = [ctypes.c_uint32, ctypes.c_char_p]
        
        self.lib.poker_strategy_table_load.restype = ctypes.c_int
        self.lib.poker_strategy_table_load.argtypes = [ctypes.c_uint32, ctypes.c_char_p]
        
        self.lib.poker_strategy_table_get_memory_usage.restype = ctypes.c_size_t
        self.lib.poker_strategy_table_get_memory_usage.argtypes = [ctypes.c_uint32]
        
        # Utility functions
        self.lib.poker_card_from_rank_suit.restype = ctypes.c_uint8
        self.lib.poker_card_from_rank_suit.argtypes = [ctypes.c_uint8, ctypes.c_uint8]
        
        self.lib.poker_card_get_rank.restype = ctypes.c_uint8
        self.lib.poker_card_get_rank.argtypes = [ctypes.c_uint8]
        
        self.lib.poker_card_get_suit.restype = ctypes.c_uint8
        self.lib.poker_card_get_suit.argtypes = [ctypes.c_uint8]
        
        # Version functions
        self.lib.poker_ai_version_major.restype = ctypes.c_uint32
        self.lib.poker_ai_version_major.argtypes = []
        
        self.lib.poker_ai_version_minor.restype = ctypes.c_uint32
        self.lib.poker_ai_version_minor.argtypes = []
        
        self.lib.poker_ai_version_patch.restype = ctypes.c_uint32
        self.lib.poker_ai_version_patch.argtypes = []
    
    def _initialize(self) -> None:
        """Initialize the Zig library."""
        error_code = self.lib.poker_ai_init()
        _check_error(error_code)
    
    def cleanup(self) -> None:
        """Cleanup the Zig library."""
        if hasattr(self, 'lib'):
            self.lib.poker_ai_cleanup()
    
    def get_version(self) -> Tuple[int, int, int]:
        """Get the Zig library version."""
        major = self.lib.poker_ai_version_major()
        minor = self.lib.poker_ai_version_minor()
        patch = self.lib.poker_ai_version_patch()
        return (major, minor, patch)

# Global library instance
_zig_lib = None

def get_zig_library() -> ZigLibrary:
    """Get the global Zig library instance."""
    global _zig_lib
    if _zig_lib is None:
        _zig_lib = ZigLibrary()
    return _zig_lib

class HandEvaluator:
    """Python wrapper for Zig hand evaluator."""
    
    def __init__(self):
        self._lib = get_zig_library()
        self._handle = self._lib.lib.poker_hand_evaluator_create()
        if self._handle == 0:
            raise AllocationError("Failed to create hand evaluator")
    
    def __del__(self):
        if hasattr(self, '_handle') and self._handle != 0:
            self._lib.lib.poker_hand_evaluator_destroy(self._handle)
    
    def evaluate_5(self, cards: List[int]) -> int:
        """Evaluate 5-card poker hand."""
        if len(cards) != 5:
            raise InvalidParameterError("Must provide exactly 5 cards")
        
        card_array = (ctypes.c_uint8 * 5)(*cards)
        result = self._lib.lib.poker_hand_evaluate_5(self._handle, card_array)
        
        if result == 0:
            raise GameStateError("Hand evaluation failed")
        
        return result
    
    def evaluate_7(self, cards: List[int]) -> int:
        """Evaluate 7-card poker hand (finds best 5-card hand)."""
        if len(cards) != 7:
            raise InvalidParameterError("Must provide exactly 7 cards")
        
        card_array = (ctypes.c_uint8 * 7)(*cards)
        result = self._lib.lib.poker_hand_evaluate_7(self._handle, card_array)
        
        if result == 0:
            raise GameStateError("Hand evaluation failed")
        
        return result

class GameState:
    """Python wrapper for Zig game state."""
    
    def __init__(self, num_players: int, small_blind: int, big_blind: int):
        if not 2 <= num_players <= 6:
            raise InvalidParameterError("Number of players must be between 2 and 6")
        
        self._lib = get_zig_library()
        self._handle = self._lib.lib.poker_game_state_create(
            num_players, small_blind, big_blind
        )
        
        if self._handle == 0:
            raise AllocationError("Failed to create game state")
    
    def __del__(self):
        if hasattr(self, '_handle') and self._handle != 0:
            self._lib.lib.poker_game_state_destroy(self._handle)
    
    def deal_hole_cards(self, player_id: int, card1: int, card2: int) -> None:
        """Deal hole cards to a player."""
        error_code = self._lib.lib.poker_game_state_deal_hole_cards(
            self._handle, player_id, card1, card2
        )
        _check_error(error_code)
    
    def apply_action(self, action_type: int, amount: int = 0) -> bool:
        """Apply an action to the game state."""
        error_code = self._lib.lib.poker_game_state_apply_action(
            self._handle, action_type, amount
        )
        _check_error(error_code)
        return True
    
    def is_terminal(self) -> bool:
        """Check if the game state is terminal."""
        result = self._lib.lib.poker_game_state_is_terminal(self._handle)
        if result == -1:
            raise GameStateError("Invalid game state handle")
        return result == 1
    
    @property
    def pot(self) -> int:
        """Get the current pot size."""
        return self._lib.lib.poker_game_state_get_pot(self._handle)
    
    @property
    def current_player(self) -> int:
        """Get the current player to act."""
        result = self._lib.lib.poker_game_state_get_current_player(self._handle)
        if result == 255:
            raise GameStateError("Invalid game state handle")
        return result

class CFRTrainer:
    """Python wrapper for Zig CFR trainer."""
    
    def __init__(self, iterations: int, num_threads: int = 1):
        self._lib = get_zig_library()
        self._handle = self._lib.lib.poker_cfr_trainer_create(iterations, num_threads)
        
        if self._handle == 0:
            raise AllocationError("Failed to create CFR trainer")
    
    def __del__(self):
        if hasattr(self, '_handle') and self._handle != 0:
            self._lib.lib.poker_cfr_trainer_destroy(self._handle)
    
    def train(self) -> None:
        """Run CFR training."""
        error_code = self._lib.lib.poker_cfr_trainer_train(self._handle)
        _check_error(error_code)
    
    def save_strategy(self, file_path: str) -> None:
        """Save trained strategy to file."""
        path_bytes = file_path.encode('utf-8')
        error_code = self._lib.lib.poker_cfr_trainer_save_strategy(
            self._handle, path_bytes
        )
        _check_error(error_code)
    
    def load_strategy(self, file_path: str) -> None:
        """Load strategy from file."""
        path_bytes = file_path.encode('utf-8')
        error_code = self._lib.lib.poker_cfr_trainer_load_strategy(
            self._handle, path_bytes
        )
        _check_error(error_code)

class StrategyTable:
    """Python wrapper for Zig strategy table."""
    
    def __init__(self):
        self._lib = get_zig_library()
        self._handle = self._lib.lib.poker_strategy_table_create()
        
        if self._handle == 0:
            raise AllocationError("Failed to create strategy table")
    
    def __del__(self):
        if hasattr(self, '_handle') and self._handle != 0:
            self._lib.lib.poker_strategy_table_destroy(self._handle)
    
    def save(self, file_path: str) -> None:
        """Save strategy table to file."""
        path_bytes = file_path.encode('utf-8')
        error_code = self._lib.lib.poker_strategy_table_save(
            self._handle, path_bytes
        )
        _check_error(error_code)
    
    def load(self, file_path: str) -> None:
        """Load strategy table from file."""
        path_bytes = file_path.encode('utf-8')
        error_code = self._lib.lib.poker_strategy_table_load(
            self._handle, path_bytes
        )
        _check_error(error_code)
    
    @property
    def memory_usage(self) -> int:
        """Get current memory usage in bytes."""
        return self._lib.lib.poker_strategy_table_get_memory_usage(self._handle)

# Utility functions
def card_from_rank_suit(rank: int, suit: int) -> int:
    """Create card from rank and suit."""
    lib = get_zig_library()
    result = lib.lib.poker_card_from_rank_suit(rank, suit)
    if result == 255:
        raise InvalidParameterError("Invalid rank or suit")
    return result

def card_get_rank(card: int) -> int:
    """Get rank from card."""
    lib = get_zig_library()
    return lib.lib.poker_card_get_rank(card)

def card_get_suit(card: int) -> int:
    """Get suit from card."""
    lib = get_zig_library()
    return lib.lib.poker_card_get_suit(card)

def get_version() -> Tuple[int, int, int]:
    """Get the Zig library version."""
    lib = get_zig_library()
    return lib.get_version()

@contextmanager
def poker_ai_context():
    """Context manager for proper library cleanup."""
    lib = get_zig_library()
    try:
        yield lib
    finally:
        lib.cleanup()

# Cleanup on module exit
import atexit
def _cleanup():
    global _zig_lib
    if _zig_lib is not None:
        _zig_lib.cleanup()

atexit.register(_cleanup)