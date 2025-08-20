"""
Game state conversion utilities between Python and Zig representations.

Handles conversion of complex game states, cards, and actions between
Python objects and the binary formats expected by the Zig library.
"""

import numpy as np
from typing import List, Dict, Any, Tuple, Optional, Union
from dataclasses import dataclass
from enum import IntEnum
import struct

# Action types (must match Zig definitions)
class ActionType(IntEnum):
    FOLD = 0
    CALL = 1
    RAISE = 2
    CHECK = 3
    ALL_IN = 4

# Game phases (must match Zig definitions)
class GamePhase(IntEnum):
    PREFLOP = 0
    FLOP = 1
    TURN = 2
    RIVER = 3

@dataclass
class PlayerState:
    """Represents a player's state in the game."""
    chips: int
    committed: int
    hole_cards: Tuple[int, int]
    is_active: bool
    is_folded: bool

@dataclass
class PythonGameState:
    """Python representation of game state."""
    num_players: int
    current_player: int
    dealer_button: int
    small_blind: int
    big_blind: int
    pot: int
    phase: GamePhase
    community_cards: List[int]
    players: List[PlayerState]
    action_history: List[Tuple[int, ActionType, int]]  # (player_id, action, amount)
    
    def __post_init__(self):
        """Validate game state after initialization."""
        if not 2 <= self.num_players <= 6:
            raise ValueError(f"Invalid number of players: {self.num_players}")
        
        if len(self.players) != self.num_players:
            raise ValueError("Player count mismatch")
        
        if not 0 <= self.current_player < self.num_players:
            raise ValueError(f"Invalid current player: {self.current_player}")

class GameStateConverter:
    """Converts between Python and Zig game state representations."""
    
    # Card conversion maps
    SUIT_ORDER = ['spades', 'hearts', 'diamonds', 'clubs']  # Match Zig ordering
    RANK_ORDER = [2, 3, 4, 5, 6, 7, 8, 9, 10, 'J', 'Q', 'K', 'A']
    
    def __init__(self):
        self._create_card_mappings()
    
    def _create_card_mappings(self):
        """Create bidirectional card mappings."""
        self.python_to_zig_card = {}
        self.zig_to_python_card = {}
        
        # Create mapping: Python card representations to Zig integers
        zig_card = 0
        for rank_idx, rank in enumerate(self.RANK_ORDER):
            for suit_idx, suit in enumerate(self.SUIT_ORDER):
                python_card = (rank, suit)
                self.python_to_zig_card[python_card] = zig_card
                self.zig_to_python_card[zig_card] = python_card
                zig_card += 1
    
    def card_to_zig(self, card: Union[Tuple[Any, str], int]) -> int:
        """Convert Python card to Zig card integer."""
        if isinstance(card, int):
            # Already in Zig format
            return card
        
        if isinstance(card, tuple) and len(card) == 2:
            rank, suit = card
            if (rank, suit) in self.python_to_zig_card:
                return self.python_to_zig_card[(rank, suit)]
        
        raise ValueError(f"Invalid card format: {card}")
    
    def card_from_zig(self, zig_card: int) -> Tuple[Any, str]:
        """Convert Zig card integer to Python card tuple."""
        if zig_card not in self.zig_to_python_card:
            raise ValueError(f"Invalid Zig card: {zig_card}")
        
        return self.zig_to_python_card[zig_card]
    
    def cards_to_zig(self, cards: List[Union[Tuple[Any, str], int]]) -> List[int]:
        """Convert list of Python cards to Zig card integers."""
        return [self.card_to_zig(card) for card in cards]
    
    def cards_from_zig(self, zig_cards: List[int]) -> List[Tuple[Any, str]]:
        """Convert list of Zig card integers to Python cards."""
        return [self.card_from_zig(card) for card in zig_cards]
    
    def action_to_zig(self, action: Dict[str, Any]) -> Tuple[int, int]:
        """Convert Python action dict to Zig action type and amount."""
        action_name = action.get('action', '').upper()
        amount = action.get('amount', 0)
        
        if action_name == 'FOLD':
            return (ActionType.FOLD, 0)
        elif action_name == 'CALL':
            return (ActionType.CALL, amount)
        elif action_name == 'RAISE':
            return (ActionType.RAISE, amount)
        elif action_name == 'CHECK':
            return (ActionType.CHECK, 0)
        elif action_name == 'ALL_IN':
            return (ActionType.ALL_IN, amount)
        else:
            raise ValueError(f"Unknown action: {action_name}")
    
    def action_from_zig(self, action_type: int, amount: int) -> Dict[str, Any]:
        """Convert Zig action to Python action dict."""
        action_type = ActionType(action_type)
        
        action_dict = {
            'action': action_type.name.lower(),
            'amount': amount
        }
        
        return action_dict
    
    def gamestate_to_zig_compatible(self, state: PythonGameState) -> Dict[str, Any]:
        """Convert Python game state to Zig-compatible representation."""
        # Convert community cards
        community_cards = self.cards_to_zig(state.community_cards)
        
        # Convert player states
        players_data = []
        for player in state.players:
            hole_card1, hole_card2 = player.hole_cards
            player_data = {
                'chips': player.chips,
                'committed': player.committed,
                'hole_card1': self.card_to_zig(hole_card1) if hole_card1 else 255,
                'hole_card2': self.card_to_zig(hole_card2) if hole_card2 else 255,
                'is_active': player.is_active,
                'is_folded': player.is_folded,
            }
            players_data.append(player_data)
        
        # Convert action history
        action_history = []
        for player_id, action_type, amount in state.action_history:
            action_history.append({
                'player_id': player_id,
                'action_type': int(action_type),
                'amount': amount,
            })
        
        return {
            'num_players': state.num_players,
            'current_player': state.current_player,
            'dealer_button': state.dealer_button,
            'small_blind': state.small_blind,
            'big_blind': state.big_blind,
            'pot': state.pot,
            'phase': int(state.phase),
            'community_cards': community_cards,
            'players': players_data,
            'action_history': action_history,
        }
    
    def gamestate_from_zig_compatible(self, zig_data: Dict[str, Any]) -> PythonGameState:
        """Convert Zig-compatible representation to Python game state."""
        # Convert community cards
        community_cards = self.cards_from_zig(zig_data['community_cards'])
        
        # Convert player states
        players = []
        for player_data in zig_data['players']:
            hole_card1 = (
                self.card_from_zig(player_data['hole_card1'])
                if player_data['hole_card1'] != 255 else None
            )
            hole_card2 = (
                self.card_from_zig(player_data['hole_card2'])
                if player_data['hole_card2'] != 255 else None
            )
            
            player = PlayerState(
                chips=player_data['chips'],
                committed=player_data['committed'],
                hole_cards=(hole_card1, hole_card2),
                is_active=player_data['is_active'],
                is_folded=player_data['is_folded'],
            )
            players.append(player)
        
        # Convert action history
        action_history = []
        for action_data in zig_data['action_history']:
            action_history.append((
                action_data['player_id'],
                ActionType(action_data['action_type']),
                action_data['amount'],
            ))
        
        return PythonGameState(
            num_players=zig_data['num_players'],
            current_player=zig_data['current_player'],
            dealer_button=zig_data['dealer_button'],
            small_blind=zig_data['small_blind'],
            big_blind=zig_data['big_blind'],
            pot=zig_data['pot'],
            phase=GamePhase(zig_data['phase']),
            community_cards=community_cards,
            players=players,
            action_history=action_history,
        )

class NumpyArrayConverter:
    """Handles conversion of numpy arrays for efficient data transfer."""
    
    @staticmethod
    def prepare_for_zig(array: np.ndarray) -> Tuple[int, int, bytes]:
        """Prepare numpy array for transfer to Zig."""
        # Ensure C-contiguous layout
        if not array.flags.c_contiguous:
            array = np.ascontiguousarray(array)
        
        # Get metadata
        dtype_code = NumpyArrayConverter._get_dtype_code(array.dtype)
        total_size = array.size
        
        # Convert to bytes
        data_bytes = array.tobytes()
        
        return dtype_code, total_size, data_bytes
    
    @staticmethod
    def restore_from_zig(dtype_code: int, shape: Tuple[int, ...], data_bytes: bytes) -> np.ndarray:
        """Restore numpy array from Zig data."""
        dtype = NumpyArrayConverter._get_dtype_from_code(dtype_code)
        array = np.frombuffer(data_bytes, dtype=dtype)
        return array.reshape(shape)
    
    @staticmethod
    def _get_dtype_code(dtype: np.dtype) -> int:
        """Get integer code for numpy dtype."""
        dtype_map = {
            np.float32: 1,
            np.float64: 2,
            np.int32: 3,
            np.int64: 4,
            np.uint32: 5,
            np.uint64: 6,
            np.uint8: 7,
        }
        
        if dtype.type not in dtype_map:
            raise ValueError(f"Unsupported dtype: {dtype}")
        
        return dtype_map[dtype.type]
    
    @staticmethod
    def _get_dtype_from_code(code: int) -> np.dtype:
        """Get numpy dtype from integer code."""
        code_map = {
            1: np.float32,
            2: np.float64,
            3: np.int32,
            4: np.int64,
            5: np.uint32,
            6: np.uint64,
            7: np.uint8,
        }
        
        if code not in code_map:
            raise ValueError(f"Unknown dtype code: {code}")
        
        return np.dtype(code_map[code])

class MemoryManager:
    """Manages memory buffers for efficient data transfer."""
    
    def __init__(self):
        self._buffers = {}
        self._next_id = 0
    
    def allocate_buffer(self, size: int) -> int:
        """Allocate a memory buffer and return its ID."""
        buffer_id = self._next_id
        self._next_id += 1
        
        self._buffers[buffer_id] = bytearray(size)
        return buffer_id
    
    def get_buffer(self, buffer_id: int) -> Optional[bytearray]:
        """Get buffer by ID."""
        return self._buffers.get(buffer_id)
    
    def write_to_buffer(self, buffer_id: int, offset: int, data: bytes) -> None:
        """Write data to buffer at offset."""
        if buffer_id not in self._buffers:
            raise ValueError(f"Buffer {buffer_id} not found")
        
        buffer = self._buffers[buffer_id]
        if offset + len(data) > len(buffer):
            raise ValueError("Data exceeds buffer size")
        
        buffer[offset:offset + len(data)] = data
    
    def read_from_buffer(self, buffer_id: int, offset: int, size: int) -> bytes:
        """Read data from buffer."""
        if buffer_id not in self._buffers:
            raise ValueError(f"Buffer {buffer_id} not found")
        
        buffer = self._buffers[buffer_id]
        if offset + size > len(buffer):
            raise ValueError("Read exceeds buffer size")
        
        return bytes(buffer[offset:offset + size])
    
    def free_buffer(self, buffer_id: int) -> None:
        """Free a memory buffer."""
        if buffer_id in self._buffers:
            del self._buffers[buffer_id]
    
    def clear_all(self) -> None:
        """Clear all buffers."""
        self._buffers.clear()
        self._next_id = 0

# Global instances
_game_state_converter = GameStateConverter()
_memory_manager = MemoryManager()

def get_converter() -> GameStateConverter:
    """Get the global game state converter."""
    return _game_state_converter

def get_memory_manager() -> MemoryManager:
    """Get the global memory manager."""
    return _memory_manager