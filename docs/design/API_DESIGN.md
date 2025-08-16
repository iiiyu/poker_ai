# Poker AI Web Service API Design

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client Apps   │────▶│   FastAPI Server  │────▶│   Poker AI      │
│  (Web/Mobile)   │◀────│   (REST + WS)     │◀────│   Engine        │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │                          │
                               ▼                          ▼
                        ┌──────────────┐          ┌──────────────┐
                        │   Redis       │          │  Trained     │
                        │   (Cache)     │          │  Models      │
                        └──────────────┘          └──────────────┘
```

## API Endpoints Design

### 1. Game Management

#### POST /api/v1/games
Create a new game session
```json
Request:
{
  "game_type": "texas_holdem",  // or "short_deck"
  "n_players": 4,
  "ai_players": [1, 2, 3],  // positions with AI
  "starting_chips": 10000,
  "small_blind": 50,
  "big_blind": 100,
  "strategy_path": "path/to/model.gz"  // optional, uses default if not provided
}

Response:
{
  "game_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "waiting_for_players",
  "created_at": "2024-01-15T10:30:00Z"
}
```

#### GET /api/v1/games/{game_id}
Get current game state
```json
Response:
{
  "game_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "in_progress",
  "current_player": 0,
  "pot": 250,
  "community_cards": ["Ah", "Kd", "7c"],
  "betting_round": "flop",
  "players": [
    {
      "position": 0,
      "chips": 9850,
      "status": "active",
      "bet": 100,
      "is_ai": false
    },
    // ... more players
  ],
  "legal_actions": ["fold", "call", "raise"],
  "min_raise": 200,
  "max_raise": 9850
}
```

### 2. AI Actions

#### POST /api/v1/games/{game_id}/ai-action
Get AI recommendation for current state
```json
Request:
{
  "player_cards": ["Ks", "Qh"],
  "community_cards": ["Ah", "Kd", "7c"],
  "pot": 250,
  "current_bet": 100,
  "player_chips": 9850,
  "opponents": [
    {"position": 1, "chips": 9900, "bet": 100},
    {"position": 2, "chips": 8500, "bet": 0}
  ],
  "betting_history": [
    {"round": "preflop", "actions": ["call", "raise", "call"]},
    {"round": "flop", "actions": ["check", "bet"]}
  ]
}

Response:
{
  "recommended_action": "raise",
  "amount": 300,
  "confidence": 0.85,
  "action_probabilities": {
    "fold": 0.05,
    "call": 0.10,
    "raise": 0.85
  },
  "expected_value": 425.50,
  "reasoning": "Strong top pair with good kicker, opponent likely has weaker holdings"
}
```

#### POST /api/v1/ai/evaluate
Evaluate a specific game situation without game context
```json
Request:
{
  "game_type": "texas_holdem",
  "player_cards": ["As", "Ac"],
  "community_cards": ["Kh", "Qd", "Jc", "10s"],
  "pot": 1000,
  "to_call": 200,
  "player_chips": 5000,
  "n_opponents": 2
}

Response:
{
  "hand_strength": 0.92,
  "win_probability": 0.78,
  "recommended_action": "raise",
  "suggested_amount": 600,
  "pot_odds": 0.167,
  "expected_value": 580
}
```

### 3. Training & Strategy

#### GET /api/v1/strategies
List available trained strategies
```json
Response:
{
  "strategies": [
    {
      "id": "default_texas_holdem",
      "game_type": "texas_holdem",
      "iterations": 100000,
      "created_at": "2024-01-10T08:00:00Z",
      "performance_rating": 0.82
    },
    {
      "id": "aggressive_short_deck",
      "game_type": "short_deck",
      "iterations": 50000,
      "created_at": "2024-01-12T15:30:00Z",
      "performance_rating": 0.75
    }
  ]
}
```

#### POST /api/v1/strategies/train
Start training a new strategy (async)
```json
Request:
{
  "game_type": "texas_holdem",
  "n_iterations": 10000,
  "n_players": 6,
  "training_params": {
    "cfr_threshold": 400,
    "discount_interval": 100
  }
}

Response:
{
  "training_id": "train_123456",
  "status": "started",
  "estimated_time": "2 hours",
  "webhook_url": "/api/v1/training/train_123456/status"
}
```

### 4. WebSocket for Real-time Games

#### WS /ws/games/{game_id}
Real-time game updates
```javascript
// Client connects
ws.connect(`/ws/games/${gameId}`)

// Server sends game state updates
{
  "type": "game_update",
  "data": {
    "action": "player_bet",
    "player": 2,
    "amount": 200,
    "pot": 450
  }
}

// Client sends action
{
  "type": "player_action",
  "data": {
    "action": "raise",
    "amount": 400
  }
}

// Server broadcasts to all clients
{
  "type": "game_update",
  "data": {
    "action": "player_raised",
    "player": 0,
    "amount": 400,
    "pot": 850,
    "next_player": 1
  }
}
```

## Data Models

### GameState
```python
class GameState:
    game_id: str
    game_type: Literal["texas_holdem", "short_deck"]
    players: List[Player]
    community_cards: List[str]
    pot: int
    current_bet: int
    betting_round: Literal["preflop", "flop", "turn", "river"]
    current_player: int
    betting_history: List[BettingRound]
```

### Player
```python
class Player:
    position: int
    chips: int
    cards: Optional[List[str]]  # Only visible to the player
    current_bet: int
    status: Literal["active", "folded", "all_in"]
    is_ai: bool
```

### Action
```python
class Action:
    action_type: Literal["fold", "call", "raise", "check", "bet"]
    amount: Optional[int]
    player: int
    timestamp: datetime
```

## Authentication & Security

### API Key Authentication
```http
GET /api/v1/games
Authorization: Bearer YOUR_API_KEY
```

### Rate Limiting
- 100 requests per minute per API key
- 10 concurrent games per user
- 1000 AI evaluations per hour

### Security Headers
```python
{
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
    "Strict-Transport-Security": "max-age=31536000"
}
```

## Error Responses

### Standard Error Format
```json
{
  "error": {
    "code": "INVALID_ACTION",
    "message": "Cannot raise less than minimum bet",
    "details": {
      "minimum_raise": 200,
      "attempted_raise": 150
    }
  },
  "request_id": "req_123456"
}
```

### Error Codes
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (invalid API key)
- `403` - Forbidden (action not allowed)
- `404` - Not Found (game/strategy not found)
- `429` - Too Many Requests (rate limit exceeded)
- `500` - Internal Server Error

## Performance Considerations

### Caching Strategy
- Cache AI decisions for identical game states (Redis, 5-minute TTL)
- Pre-load frequently used strategies in memory
- Use connection pooling for database connections

### Async Processing
- Training runs in background workers (Celery)
- WebSocket connections handled by separate process
- AI calculations in thread pool to avoid blocking

### Scalability
- Horizontal scaling with load balancer
- Stateless API servers
- Redis for session management
- PostgreSQL for game history
- S3/MinIO for strategy storage

## Client SDK Examples

### Python
```python
from poker_ai_client import PokerAIClient

client = PokerAIClient(api_key="your_key")

# Create game
game = client.create_game(
    game_type="texas_holdem",
    n_players=4
)

# Get AI action
action = client.get_ai_action(
    game_id=game.id,
    player_cards=["As", "Ks"],
    community_cards=["Ah", "Kd", "7c"]
)

print(f"AI recommends: {action.recommended_action}")
```

### JavaScript
```javascript
const client = new PokerAIClient({ apiKey: 'your_key' });

// Connect to game via WebSocket
const game = await client.connectGame(gameId);

game.on('update', (state) => {
  console.log('Game updated:', state);
});

// Get AI recommendation
const action = await client.getAIAction({
  playerCards: ['As', 'Ks'],
  communityCards: ['Ah', 'Kd', '7c']
});

// Execute action
await game.sendAction(action.recommendedAction, action.amount);
```

## Deployment Architecture

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    image: poker-ai-api:latest
    ports:
      - "8000:8000"
    environment:
      - REDIS_URL=redis://redis:6379
      - DATABASE_URL=postgresql://postgres:password@db:5432/poker
    depends_on:
      - redis
      - db
    
  worker:
    image: poker-ai-api:latest
    command: celery worker
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=poker
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Monitoring & Analytics

### Metrics to Track
- API response times
- AI decision calculation time
- Cache hit rates
- Active games count
- Training job queue length

### Logging
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "service": "poker-ai-api",
  "request_id": "req_123456",
  "user_id": "user_789",
  "action": "ai_decision",
  "game_id": "game_abc",
  "duration_ms": 45,
  "result": "success"
}
```

## API Versioning

- URL versioning: `/api/v1/`, `/api/v2/`
- Deprecation notices in headers
- 6-month deprecation period
- Backward compatibility for critical endpoints