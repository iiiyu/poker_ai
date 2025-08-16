# Poker AI API - Quick Start Guide

## 🚀 Start in 30 Seconds

```bash
# Start with Docker (default)
./start_api.sh docker

# OR start with Podman
./start_api.sh podman

# OR start in local development mode (uses uv)
./start_api.sh local

# API will be available at:
# - http://localhost:8000 (API)
# - http://localhost:8000/docs (Interactive docs)
```

## 🔧 Prerequisites

### Option 1: Docker
```bash
# Install Docker from https://docs.docker.com/get-docker/
```

### Option 2: Podman (Recommended for macOS/Linux)
```bash
# Install Podman
brew install podman  # macOS
# OR
sudo apt install podman  # Ubuntu/Debian
# OR  
sudo dnf install podman  # Fedora

# Initialize and start Podman machine (macOS only)
podman machine init
podman machine start
```

### Option 3: Local Development
```bash
# Install uv (Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# The script will handle all Python dependencies automatically
```

## 🧪 Test the API

```bash
# Run test suite
./start_api.sh test
```

## 📝 Quick Example

```python
import requests

# Create a game
response = requests.post("http://localhost:8000/api/v1/games", json={
    "game_type": "texas_holdem",
    "n_players": 4,
    "ai_players": [1, 2, 3]
})
game = response.json()

# Get AI recommendation
response = requests.post(f"http://localhost:8000/api/v1/games/{game['game_id']}/ai-action", json={
    "player_cards": ["As", "Ks"],
    "community_cards": ["Ah", "Kd", "7c"],
    "pot": 500,
    "current_bet": 100,
    "player_chips": 9500,
    "opponents": [],
    "betting_history": []
})
action = response.json()
print(f"AI recommends: {action['recommended_action']}")
```

## 🛑 Stop Services

```bash
./start_api.sh stop
```

## 📚 Full Documentation

See [API_README.md](API_README.md) for complete documentation.