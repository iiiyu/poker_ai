"""Pydantic models for API requests and responses."""

from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Any
from uuid import UUID

from pydantic import BaseModel, Field, validator


class GameType(str, Enum):
    TEXAS_HOLDEM = "texas_holdem"
    # Kept for backward compatibility but will always use texas_holdem
    SHORT_DECK = "short_deck"  # DEPRECATED - maps to texas_holdem


class BettingRound(str, Enum):
    PREFLOP = "preflop"
    FLOP = "flop"
    TURN = "turn"
    RIVER = "river"


class PlayerStatus(str, Enum):
    ACTIVE = "active"
    FOLDED = "folded"
    ALL_IN = "all_in"


class ActionType(str, Enum):
    FOLD = "fold"
    CALL = "call"
    RAISE = "raise"
    CHECK = "check"
    BET = "bet"


# Request Models
class CreateGameRequest(BaseModel):
    game_type: GameType = GameType.TEXAS_HOLDEM
    n_players: int = Field(ge=2, le=8)
    ai_players: List[int] = Field(default_factory=list)
    starting_chips: int = Field(default=10000, gt=0)
    small_blind: int = Field(default=50, gt=0)
    big_blind: int = Field(default=100, gt=0)
    strategy_path: Optional[str] = None

    @validator("ai_players")
    def validate_ai_players(cls, v, values):
        if "n_players" in values:
            if any(p >= values["n_players"] or p < 0 for p in v):
                raise ValueError("Invalid AI player positions")
        return v


class PlayerInfo(BaseModel):
    position: int
    chips: int
    status: PlayerStatus
    bet: int
    is_ai: bool
    cards: Optional[List[str]] = None  # Only visible to the player


class GameStateResponse(BaseModel):
    game_id: UUID
    status: str
    current_player: int
    pot: int
    community_cards: List[str]
    betting_round: BettingRound
    players: List[PlayerInfo]
    legal_actions: List[ActionType]
    min_raise: Optional[int] = None
    max_raise: Optional[int] = None
    created_at: datetime
    updated_at: datetime


class OpponentInfo(BaseModel):
    position: int
    chips: int
    bet: int


class BettingHistory(BaseModel):
    round: BettingRound
    actions: List[str]


class AIActionRequest(BaseModel):
    player_cards: List[str] = Field(min_items=2, max_items=2)
    community_cards: List[str] = Field(max_items=5)
    pot: int = Field(gt=0)
    current_bet: int = Field(ge=0)
    player_chips: int = Field(gt=0)
    opponents: List[OpponentInfo]
    betting_history: List[BettingHistory] = Field(default_factory=list)

    @validator("player_cards", "community_cards")
    def validate_cards(cls, v):
        valid_cards = {
            f"{rank}{suit}"
            for rank in ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
            for suit in ["h", "d", "c", "s"]
        }
        for card in v:
            if card not in valid_cards:
                raise ValueError(f"Invalid card: {card}")
        return v


class AIActionResponse(BaseModel):
    recommended_action: ActionType
    amount: Optional[int] = None
    confidence: float = Field(ge=0, le=1)
    action_probabilities: Dict[str, float]
    expected_value: float
    reasoning: Optional[str] = None


class EvaluateRequest(BaseModel):
    game_type: GameType = GameType.TEXAS_HOLDEM
    player_cards: List[str] = Field(min_items=2, max_items=2)
    community_cards: List[str] = Field(max_items=5)
    pot: int = Field(gt=0)
    to_call: int = Field(ge=0)
    player_chips: int = Field(gt=0)
    n_opponents: int = Field(ge=1, le=7)


class EvaluateResponse(BaseModel):
    hand_strength: float = Field(ge=0, le=1)
    win_probability: float = Field(ge=0, le=1)
    recommended_action: ActionType
    suggested_amount: Optional[int] = None
    pot_odds: float
    expected_value: float


class StrategyInfo(BaseModel):
    id: str
    game_type: GameType
    iterations: int
    created_at: datetime
    performance_rating: float = Field(ge=0, le=1)
    file_size_mb: float
    description: Optional[str] = None


class TrainStrategyRequest(BaseModel):
    game_type: GameType = GameType.TEXAS_HOLDEM
    n_iterations: int = Field(default=10000, ge=100, le=1000000)
    n_players: int = Field(default=6, ge=2, le=8)
    training_params: Dict[str, Any] = Field(default_factory=dict)


class TrainStrategyResponse(BaseModel):
    training_id: str
    status: str
    estimated_time: str
    webhook_url: str


class PlayerActionRequest(BaseModel):
    action: ActionType
    amount: Optional[int] = None

    @validator("amount")
    def validate_amount(cls, v, values):
        if values.get("action") == ActionType.RAISE and v is None:
            raise ValueError("Amount required for raise action")
        return v


# WebSocket Messages
class WSMessage(BaseModel):
    type: str
    data: Dict[str, Any]
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class WSGameUpdate(BaseModel):
    action: str
    player: Optional[int] = None
    amount: Optional[int] = None
    pot: int
    next_player: Optional[int] = None
    community_cards: Optional[List[str]] = None
    winners: Optional[List[int]] = None


# Error Response
class ErrorDetail(BaseModel):
    code: str
    message: str
    details: Optional[Dict[str, Any]] = None


class ErrorResponse(BaseModel):
    error: ErrorDetail
    request_id: str


# Health Check
class HealthResponse(BaseModel):
    status: str
    version: str
    timestamp: datetime
    services: Dict[str, bool]