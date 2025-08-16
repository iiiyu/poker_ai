"""Main FastAPI application for Poker AI Web Service."""

import os
import sys
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
from uuid import UUID, uuid4

import joblib
from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from redis import asyncio as aioredis

# Add parent directory to path to import poker_ai
sys.path.append(str(Path(__file__).parent.parent))

from poker_ai.games.factory import create_poker_game
from poker_ai.ai.agent import Agent
from poker_ai.ai import ai as ai_module

from api.models import (
    CreateGameRequest, GameStateResponse, PlayerInfo,
    AIActionRequest, AIActionResponse,
    EvaluateRequest, EvaluateResponse,
    StrategyInfo, TrainStrategyRequest, TrainStrategyResponse,
    PlayerActionRequest, WSMessage, WSGameUpdate,
    ErrorResponse, ErrorDetail, HealthResponse,
    GameType, ActionType, PlayerStatus, BettingRound
)


# Global storage (in production, use database)
games_store: Dict[UUID, dict] = {}
strategies_store: Dict[str, Agent] = {}
redis_client: Optional[aioredis.Redis] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    # Startup
    print("Starting Poker AI API...")
    
    # Initialize Redis connection
    global redis_client
    try:
        redis_client = await aioredis.from_url(
            os.getenv("REDIS_URL", "redis://localhost:6379"),
            decode_responses=True
        )
        await redis_client.ping()
        print("Connected to Redis")
    except Exception as e:
        print(f"Redis connection failed: {e}")
        redis_client = None
    
    # Load default strategies
    load_default_strategies()
    
    yield
    
    # Shutdown
    print("Shutting down Poker AI API...")
    if redis_client:
        await redis_client.close()


app = FastAPI(
    title="Poker AI API",
    description="Web service for poker AI decisions and game management",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def load_default_strategies():
    """Load pre-trained strategies."""
    # Try to load default strategies if they exist
    strategy_dir = Path("strategies")
    if strategy_dir.exists():
        for strategy_file in strategy_dir.glob("*.joblib"):
            try:
                strategy_id = strategy_file.stem
                strategies_store[strategy_id] = joblib.load(strategy_file)
                print(f"Loaded strategy: {strategy_id}")
            except Exception as e:
                print(f"Failed to load strategy {strategy_file}: {e}")


# Dependency injection
async def get_redis():
    """Get Redis client."""
    if redis_client is None:
        raise HTTPException(status_code=503, detail="Redis unavailable")
    return redis_client


# API Endpoints

@app.get("/", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        timestamp=datetime.utcnow(),
        services={
            "api": True,
            "redis": redis_client is not None,
            "strategies_loaded": len(strategies_store) > 0
        }
    )


@app.post("/api/v1/games", response_model=Dict)
async def create_game(request: CreateGameRequest):
    """Create a new poker game."""
    game_id = uuid4()
    
    try:
        # Create game state
        game_state = create_poker_game(
            request.game_type.value,
            n_players=request.n_players
        )
        
        # Store game information
        game_data = {
            "id": game_id,
            "type": request.game_type,
            "state": game_state,
            "players": [
                {
                    "position": i,
                    "chips": request.starting_chips,
                    "is_ai": i in request.ai_players,
                    "status": PlayerStatus.ACTIVE
                }
                for i in range(request.n_players)
            ],
            "pot": 0,
            "small_blind": request.small_blind,
            "big_blind": request.big_blind,
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow(),
            "betting_round": BettingRound.PREFLOP,
            "current_player": 0,
            "community_cards": [],
            "strategy_path": request.strategy_path
        }
        
        games_store[game_id] = game_data
        
        return {
            "game_id": str(game_id),
            "status": "created",
            "created_at": game_data["created_at"].isoformat()
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/games/{game_id}", response_model=GameStateResponse)
async def get_game_state(game_id: UUID):
    """Get current game state."""
    if game_id not in games_store:
        raise HTTPException(status_code=404, detail="Game not found")
    
    game = games_store[game_id]
    
    return GameStateResponse(
        game_id=game_id,
        status="in_progress",
        current_player=game["current_player"],
        pot=game["pot"],
        community_cards=game["community_cards"],
        betting_round=game["betting_round"],
        players=[
            PlayerInfo(
                position=p["position"],
                chips=p["chips"],
                status=p["status"],
                bet=p.get("bet", 0),
                is_ai=p["is_ai"]
            )
            for p in game["players"]
        ],
        legal_actions=[ActionType.FOLD, ActionType.CALL, ActionType.RAISE],
        min_raise=game["big_blind"] * 2,
        max_raise=min(p["chips"] for p in game["players"]),
        created_at=game["created_at"],
        updated_at=game["updated_at"]
    )


@app.post("/api/v1/games/{game_id}/ai-action", response_model=AIActionResponse)
async def get_ai_action(game_id: UUID, request: AIActionRequest):
    """Get AI recommendation for current game state."""
    
    # Check if game exists
    if game_id not in games_store:
        raise HTTPException(status_code=404, detail="Game not found")
    
    try:
        # Calculate hand strength and determine action
        # This is a simplified version - in production, use the actual AI model
        
        # Simple heuristic for demonstration
        hand_strength = calculate_hand_strength(
            request.player_cards,
            request.community_cards
        )
        
        # Determine action based on hand strength and pot odds
        pot_odds = request.current_bet / (request.pot + request.current_bet) if request.current_bet > 0 else 0
        
        if hand_strength > 0.8:
            action = ActionType.RAISE
            amount = min(request.pot // 2, request.player_chips)
            confidence = 0.9
        elif hand_strength > 0.5 and pot_odds < 0.3:
            action = ActionType.CALL
            amount = request.current_bet
            confidence = 0.7
        elif hand_strength > 0.3 and request.current_bet == 0:
            action = ActionType.CHECK
            amount = 0
            confidence = 0.6
        else:
            action = ActionType.FOLD
            amount = 0
            confidence = 0.8
        
        return AIActionResponse(
            recommended_action=action,
            amount=amount if action == ActionType.RAISE else None,
            confidence=confidence,
            action_probabilities={
                "fold": 0.2 if hand_strength > 0.5 else 0.6,
                "call": 0.3 if hand_strength > 0.5 else 0.3,
                "raise": 0.5 if hand_strength > 0.5 else 0.1
            },
            expected_value=request.pot * hand_strength,
            reasoning=f"Hand strength: {hand_strength:.2f}, Pot odds: {pot_odds:.2f}"
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/ai/evaluate", response_model=EvaluateResponse)
async def evaluate_situation(request: EvaluateRequest):
    """Evaluate a poker situation without game context."""
    
    try:
        # Calculate hand strength
        hand_strength = calculate_hand_strength(
            request.player_cards,
            request.community_cards
        )
        
        # Calculate pot odds
        pot_odds = request.to_call / (request.pot + request.to_call) if request.to_call > 0 else 0
        
        # Simple win probability estimation
        win_probability = hand_strength ** (1 / max(1, request.n_opponents))
        
        # Determine recommended action
        if win_probability > pot_odds + 0.1:
            action = ActionType.RAISE
            suggested_amount = min(request.pot // 2, request.player_chips)
        elif win_probability > pot_odds:
            action = ActionType.CALL
            suggested_amount = request.to_call
        else:
            action = ActionType.FOLD
            suggested_amount = 0
        
        # Calculate expected value
        ev = (win_probability * request.pot) - ((1 - win_probability) * request.to_call)
        
        return EvaluateResponse(
            hand_strength=hand_strength,
            win_probability=win_probability,
            recommended_action=action,
            suggested_amount=suggested_amount if action == ActionType.RAISE else None,
            pot_odds=pot_odds,
            expected_value=ev
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/strategies", response_model=List[StrategyInfo])
async def list_strategies():
    """List available trained strategies."""
    strategies = []
    
    # Add loaded strategies
    for strategy_id in strategies_store:
        strategies.append(
            StrategyInfo(
                id=strategy_id,
                game_type=GameType.TEXAS_HOLDEM,  # Default for now
                iterations=10000,  # Placeholder
                created_at=datetime.utcnow(),
                performance_rating=0.75,  # Placeholder
                file_size_mb=1.5,  # Placeholder
                description="Pre-trained strategy"
            )
        )
    
    # Add default strategies
    if not strategies:
        strategies.append(
            StrategyInfo(
                id="default_conservative",
                game_type=GameType.TEXAS_HOLDEM,
                iterations=50000,
                created_at=datetime.utcnow(),
                performance_rating=0.70,
                file_size_mb=2.3,
                description="Conservative playing style"
            )
        )
        strategies.append(
            StrategyInfo(
                id="default_aggressive",
                game_type=GameType.TEXAS_HOLDEM,
                iterations=50000,
                created_at=datetime.utcnow(),
                performance_rating=0.75,
                file_size_mb=2.3,
                description="Aggressive playing style"
            )
        )
    
    return strategies


@app.post("/api/v1/strategies/train", response_model=TrainStrategyResponse)
async def train_strategy(request: TrainStrategyRequest):
    """Start training a new strategy (async)."""
    training_id = f"train_{uuid4().hex[:8]}"
    
    # In production, this would start a Celery task
    # For now, return a mock response
    estimated_hours = (request.n_iterations / 1000) * 0.1  # Rough estimate
    
    return TrainStrategyResponse(
        training_id=training_id,
        status="queued",
        estimated_time=f"{estimated_hours:.1f} hours",
        webhook_url=f"/api/v1/training/{training_id}/status"
    )


# WebSocket endpoint for real-time games
@app.websocket("/ws/games/{game_id}")
async def websocket_game(websocket: WebSocket, game_id: UUID):
    """WebSocket endpoint for real-time game updates."""
    await websocket.accept()
    
    if game_id not in games_store:
        await websocket.send_json({
            "type": "error",
            "data": {"message": "Game not found"}
        })
        await websocket.close()
        return
    
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_json()
            
            if data["type"] == "player_action":
                # Process player action
                action_data = data["data"]
                
                # Update game state (simplified)
                game = games_store[game_id]
                game["updated_at"] = datetime.utcnow()
                
                # Broadcast update to all clients
                update = WSGameUpdate(
                    action=f"player_{action_data['action']}",
                    player=game["current_player"],
                    amount=action_data.get("amount"),
                    pot=game["pot"],
                    next_player=(game["current_player"] + 1) % len(game["players"])
                )
                
                await websocket.send_json({
                    "type": "game_update",
                    "data": update.dict()
                })
                
    except WebSocketDisconnect:
        print(f"Client disconnected from game {game_id}")
    except Exception as e:
        print(f"WebSocket error: {e}")
        await websocket.close()


# Helper functions
def calculate_hand_strength(player_cards: List[str], community_cards: List[str]) -> float:
    """Calculate hand strength (simplified version)."""
    # This is a placeholder - in production, use actual hand evaluation
    
    # Simple heuristic based on high cards
    card_values = {"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, 
                   "8": 8, "9": 9, "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14}
    
    player_values = [card_values.get(card[0], 0) for card in player_cards]
    
    # Check for pairs
    if player_values[0] == player_values[1]:
        return min(0.5 + (player_values[0] / 28), 0.95)
    
    # High cards
    return min(max(player_values) / 14 * 0.5, 0.5)


# Error handlers
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    """Handle HTTP exceptions."""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": f"HTTP_{exc.status_code}",
                "message": exc.detail
            },
            "request_id": str(uuid4())
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request, exc):
    """Handle general exceptions."""
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "An internal error occurred"
            },
            "request_id": str(uuid4())
        }
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)