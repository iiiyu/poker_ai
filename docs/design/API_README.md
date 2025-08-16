# Poker AI Web Service API

A FastAPI-based web service that provides poker AI decision-making capabilities through REST APIs and WebSocket connections.

## Features

- 🎮 **Game Management**: Create and manage poker games (Texas Hold'em & Short Deck)
- 🤖 **AI Decisions**: Get AI-recommended actions for any game state
- 🔄 **Real-time Updates**: WebSocket support for live game updates
- 📊 **Hand Evaluation**: Analyze poker hands and get win probabilities
- 🎯 **Strategy Management**: Load and use different AI strategies
- 🐳 **Container Ready**: Full Docker/Podman Compose setup for easy deployment
- 🚀 **Modern Tooling**: Built with uv for fast Python dependency management

## Quick Start

### Using the Startup Script (Recommended)

```bash
# Start with Docker
./start_api.sh docker

# OR start with Podman
./start_api.sh podman

# OR start in local development mode
./start_api.sh local

# API will be available at http://localhost:8000
# API docs at http://localhost:8000/docs
```

### Manual Setup

#### Option 1: Docker

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

#### Option 2: Podman

```bash
# Initialize Podman machine (macOS only)
podman machine init
podman machine start

# Start services
podman-compose up -d

# View logs
podman-compose logs -f

# Stop services
podman-compose down
```

#### Option 3: Local Development with uv

```bash
# Install uv if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Sync project dependencies
uv sync

# Install API dependencies
uv pip install -r api/requirements.txt

# Start Redis
podman run -d -p 6379:6379 redis:7-alpine
# OR
docker run -d -p 6379:6379 redis:7-alpine

# Run the API
uv run uvicorn api.main:app --reload

# Visit http://localhost:8000/docs for interactive API documentation
```

## API Endpoints

### 1. Create a Game

```bash
curl -X POST "http://localhost:8000/api/v1/games" \
  -H "Content-Type: application/json" \
  -d '{
    "game_type": "texas_holdem",
    "n_players": 4,
    "ai_players": [1, 2, 3],
    "starting_chips": 10000,
    "small_blind": 50,
    "big_blind": 100
  }'
```

**Response:**
```json
{
  "game_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "created",
  "created_at": "2024-01-15T10:30:00Z"
}
```

### 2. Get AI Action Recommendation

```bash
curl -X POST "http://localhost:8000/api/v1/games/{game_id}/ai-action" \
  -H "Content-Type: application/json" \
  -d '{
    "player_cards": ["As", "Ks"],
    "community_cards": ["Ah", "Kd", "7c"],
    "pot": 500,
    "current_bet": 100,
    "player_chips": 9500,
    "opponents": [
      {"position": 1, "chips": 9900, "bet": 100}
    ],
    "betting_history": []
  }'
```

**Response:**
```json
{
  "recommended_action": "raise",
  "amount": 300,
  "confidence": 0.85,
  "action_probabilities": {
    "fold": 0.05,
    "call": 0.10,
    "raise": 0.85
  },
  "expected_value": 625.50,
  "reasoning": "Strong two pair with top kicker"
}
```

### 3. Evaluate Hand Strength

```bash
curl -X POST "http://localhost:8000/api/v1/ai/evaluate" \
  -H "Content-Type: application/json" \
  -d '{
    "game_type": "texas_holdem",
    "player_cards": ["Ac", "Ad"],
    "community_cards": ["Kh", "Qd", "Jc"],
    "pot": 1000,
    "to_call": 200,
    "player_chips": 5000,
    "n_opponents": 2
  }'
```

**Response:**
```json
{
  "hand_strength": 0.85,
  "win_probability": 0.72,
  "recommended_action": "raise",
  "suggested_amount": 500,
  "pot_odds": 0.167,
  "expected_value": 520
}
```

### 4. WebSocket Connection

```javascript
// JavaScript WebSocket client example
const ws = new WebSocket('ws://localhost:8000/ws/games/550e8400-e29b-41d4-a716-446655440000');

ws.onopen = () => {
  console.log('Connected to game');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Game update:', data);
};

// Send player action
ws.send(JSON.stringify({
  type: 'player_action',
  data: {
    action: 'raise',
    amount: 200
  }
}));
```

## Python Client Example

```python
import requests
import json

class PokerAIClient:
    def __init__(self, base_url="http://localhost:8000"):
        self.base_url = base_url
        
    def create_game(self, n_players=4, game_type="texas_holdem"):
        """Create a new game."""
        response = requests.post(
            f"{self.base_url}/api/v1/games",
            json={
                "game_type": game_type,
                "n_players": n_players,
                "ai_players": list(range(1, n_players)),
                "starting_chips": 10000
            }
        )
        return response.json()
    
    def get_ai_action(self, game_id, player_cards, community_cards, pot, current_bet):
        """Get AI recommendation."""
        response = requests.post(
            f"{self.base_url}/api/v1/games/{game_id}/ai-action",
            json={
                "player_cards": player_cards,
                "community_cards": community_cards,
                "pot": pot,
                "current_bet": current_bet,
                "player_chips": 10000,
                "opponents": [],
                "betting_history": []
            }
        )
        return response.json()

# Example usage
client = PokerAIClient()

# Create a game
game = client.create_game(n_players=4)
print(f"Created game: {game['game_id']}")

# Get AI action
action = client.get_ai_action(
    game_id=game['game_id'],
    player_cards=["As", "Ks"],
    community_cards=["Ah", "Kd", "7c"],
    pot=500,
    current_bet=100
)
print(f"AI recommends: {action['recommended_action']}")
```

## JavaScript/TypeScript Client Example

```typescript
interface GameResponse {
  game_id: string;
  status: string;
  created_at: string;
}

interface AIActionResponse {
  recommended_action: string;
  amount?: number;
  confidence: number;
  action_probabilities: Record<string, number>;
  expected_value: number;
  reasoning?: string;
}

class PokerAIClient {
  private baseUrl: string;

  constructor(baseUrl = 'http://localhost:8000') {
    this.baseUrl = baseUrl;
  }

  async createGame(nPlayers = 4): Promise<GameResponse> {
    const response = await fetch(`${this.baseUrl}/api/v1/games`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        game_type: 'texas_holdem',
        n_players: nPlayers,
        ai_players: Array.from({ length: nPlayers - 1 }, (_, i) => i + 1),
        starting_chips: 10000
      })
    });
    return response.json();
  }

  async getAIAction(
    gameId: string,
    playerCards: string[],
    communityCards: string[]
  ): Promise<AIActionResponse> {
    const response = await fetch(
      `${this.baseUrl}/api/v1/games/${gameId}/ai-action`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          player_cards: playerCards,
          community_cards: communityCards,
          pot: 500,
          current_bet: 100,
          player_chips: 10000,
          opponents: [],
          betting_history: []
        })
      }
    );
    return response.json();
  }
}

// Usage
const client = new PokerAIClient();

async function playHand() {
  const game = await client.createGame(4);
  console.log(`Game created: ${game.game_id}`);
  
  const action = await client.getAIAction(
    game.game_id,
    ['As', 'Ks'],
    ['Ah', 'Kd', '7c']
  );
  
  console.log(`AI recommends: ${action.recommended_action}`);
  if (action.amount) {
    console.log(`Amount: ${action.amount}`);
  }
}

playHand();
```

## API Authentication (Optional)

To enable API key authentication, set the `API_KEY` environment variable:

```bash
# docker-compose.yml
environment:
  - API_KEY=your-secret-api-key

# Client usage
curl -X POST "http://localhost:8000/api/v1/games" \
  -H "Authorization: Bearer your-secret-api-key" \
  -H "Content-Type: application/json" \
  -d '{...}'
```

## Load Custom Strategies

Place your trained strategy files (`.joblib` or `.gz`) in the `strategies/` directory:

```bash
# Copy strategy file
cp path/to/offline_strategy_10000.gz strategies/my_strategy.gz

# Restart API to load
docker-compose restart api
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `REDIS_URL` | Redis connection URL | `redis://localhost:6379` |
| `DATABASE_URL` | PostgreSQL connection URL | `postgresql://postgres:postgres@localhost:5432/poker_ai` |
| `API_KEY` | Optional API key for authentication | None |
| `MAX_GAMES_PER_USER` | Maximum concurrent games | 10 |
| `STRATEGY_CACHE_TTL` | Strategy cache TTL in seconds | 300 |

## Production Deployment

### Using Docker Swarm

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c docker-compose.yml poker-ai

# Scale API servers
docker service scale poker-ai_api=3
```

### Using Podman with systemd (Recommended for Linux servers)

```bash
# Generate systemd units from the compose file
podman-compose systemd -a create-unit

# Enable and start the service
systemctl --user enable podman-compose@poker-ai
systemctl --user start podman-compose@poker-ai

# Check status
systemctl --user status podman-compose@poker-ai
```

### Using Kubernetes

```yaml
# kubernetes/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: poker-ai-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: poker-ai-api
  template:
    metadata:
      labels:
        app: poker-ai-api
    spec:
      containers:
      - name: api
        image: poker-ai-api:latest
        ports:
        - containerPort: 8000
        env:
        - name: REDIS_URL
          value: redis://redis-service:6379
```

### Using AWS/GCP/Azure

1. Build and push container image:
```bash
# Using Docker
docker build -f api/Dockerfile -t poker-ai-api .
docker tag poker-ai-api:latest your-registry/poker-ai-api:latest
docker push your-registry/poker-ai-api:latest

# OR using Podman
podman build -f api/Dockerfile -t poker-ai-api .
podman tag poker-ai-api:latest your-registry/poker-ai-api:latest
podman push your-registry/poker-ai-api:latest
```

2. Deploy using cloud services:
- AWS: ECS, EKS, or Elastic Beanstalk
- GCP: Cloud Run, GKE, or App Engine
- Azure: Container Instances, AKS, or App Service

## Monitoring

### Health Check
```bash
curl http://localhost:8000/
```

### Metrics Endpoint
```bash
curl http://localhost:8000/metrics
```

### Logs
```bash
# View API logs (Docker)
docker-compose logs -f api

# View API logs (Podman)
podman-compose logs -f api

# View all logs
docker-compose logs -f
# OR
podman-compose logs -f
```

## Testing

```bash
# Run tests using the startup script
./start_api.sh test

# Run unit tests manually
uv run pytest api/tests/

# Run integration tests
./start_api.sh docker  # or podman
uv run pytest api/tests/integration/

# Load testing with locust
uv pip install locust
uv run locust -f api/tests/locustfile.py --host=http://localhost:8000
```

## Troubleshooting

### Container Runtime Issues

#### Podman Machine Not Running (macOS)
```bash
# Check machine status
podman machine list

# Start the machine
podman machine start

# If issues persist, recreate the machine
podman machine rm
podman machine init
podman machine start
```

#### Docker/Podman Permission Issues
```bash
# For Docker, add user to docker group (Linux)
sudo usermod -aG docker $USER

# For Podman, no root required - runs rootless by default
```

### Redis Connection Error
```bash
# Check Redis is running (Docker)
docker-compose ps redis

# Check Redis is running (Podman)
podman-compose ps redis

# Test Redis connection
redis-cli ping
```

### Port Already in Use
```bash
# Change port in docker-compose.yml
ports:
  - "8001:8000"  # Use 8001 instead

# OR use different port with startup script
PORT=8001 ./start_api.sh local
```

### Strategy Not Loading
```bash
# Check strategy file permissions
ls -la strategies/

# Check API logs for errors
./start_api.sh docker
docker-compose logs api | grep -i strategy
# OR for Podman
podman-compose logs api | grep -i strategy
```

### Podman-compose Not Found
```bash
# Install with pipx (recommended)
pipx install podman-compose

# OR install with pip
pip3 install --user podman-compose

# OR install with Homebrew (macOS)
brew install podman-compose
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

GPL-3.0 License - See LICENSE file for details

## Support

- Documentation: [API Docs](http://localhost:8000/docs)
- Issues: [GitHub Issues](https://github.com/fedden/poker_ai/issues)
- Email: support@pokerai.example.com