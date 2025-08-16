#!/bin/bash

# Poker AI API Startup Script

echo "======================================"
echo "  Poker AI Web Service Launcher"
echo "======================================"
echo ""

# Detect container runtime (prefer Podman if available)
CONTAINER_RUNTIME=""
COMPOSE_COMMAND=""

if command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
    if command -v podman-compose &> /dev/null; then
        COMPOSE_COMMAND="podman-compose"
    elif command -v docker-compose &> /dev/null; then
        # Podman can use docker-compose with podman socket
        COMPOSE_COMMAND="docker-compose"
        export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
    else
        echo "⚠️  podman-compose not found. Installing..."
        echo "Run: pip3 install podman-compose"
    fi
elif command -v docker &> /dev/null; then
    CONTAINER_RUNTIME="docker"
    if command -v docker-compose &> /dev/null; then
        COMPOSE_COMMAND="docker-compose"
    fi
else
    echo "❌ Neither Podman nor Docker is installed."
    echo "Install Podman: https://podman.io/getting-started/installation"
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if [ -z "$COMPOSE_COMMAND" ]; then
    echo "❌ No compose command found. Please install:"
    echo "  For Podman: pip3 install podman-compose"
    echo "  For Docker: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "Using container runtime: $CONTAINER_RUNTIME"
echo "Using compose command: $COMPOSE_COMMAND"
echo ""

# Parse command line arguments
MODE=${1:-docker}

case $MODE in
    docker|podman)
        echo "Starting services with $COMPOSE_COMMAND..."
        echo ""
        
        # Create strategies directory if it doesn't exist
        mkdir -p strategies
        
        # Start services
        $COMPOSE_COMMAND up -d
        
        # Wait for services to be ready
        echo ""
        echo "Waiting for services to start..."
        sleep 5
        
        # Check if API is responding
        if curl -s http://localhost:8000/ > /dev/null; then
            echo "✅ API is running at http://localhost:8000"
            echo "📚 Documentation at http://localhost:8000/docs"
            echo ""
            echo "To view logs: $COMPOSE_COMMAND logs -f"
            echo "To stop: $COMPOSE_COMMAND down"
        else
            echo "⚠️  API might still be starting up..."
            echo "Check logs: $COMPOSE_COMMAND logs api"
        fi
        ;;
        
    local)
        echo "Starting API in local development mode..."
        echo ""
        
        # Check Python version
        if ! python3 --version | grep -E "3\.(12|11|10)" > /dev/null; then
            echo "⚠️  Python 3.10+ is recommended"
        fi
        
        # Start Redis in container
        echo "Starting Redis..."
        $CONTAINER_RUNTIME run -d --name poker-redis -p 6379:6379 redis:7-alpine
        
        # Install dependencies if needed
        if [ ! -d "venv" ]; then
            echo "Creating virtual environment..."
            python3 -m venv venv
            source venv/bin/activate
            pip install -r api/requirements.txt
            pip install -e .
        else
            source venv/bin/activate
        fi
        
        # Start the API
        echo ""
        echo "Starting API server..."
        uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
        ;;
        
    test)
        echo "Running API tests..."
        echo ""
        
        # Check if API is running
        if ! curl -s http://localhost:8000/ > /dev/null; then
            echo "❌ API is not running. Start it first with:"
            echo "   ./start_api.sh docker  (or ./start_api.sh podman)"
            exit 1
        fi
        
        # Run tests
        python3 api/test_api.py
        ;;
        
    stop)
        echo "Stopping all services..."
        $COMPOSE_COMMAND down 2>/dev/null || true
        $CONTAINER_RUNTIME stop poker-redis 2>/dev/null || true
        $CONTAINER_RUNTIME rm poker-redis 2>/dev/null || true
        echo "✅ Services stopped"
        ;;
        
    *)
        echo "Usage: $0 [docker|podman|local|test|stop]"
        echo ""
        echo "  docker  - Run with Docker Compose"
        echo "  podman  - Run with Podman Compose (uses same config)"
        echo "  local   - Run locally for development"
        echo "  test    - Run API tests"
        echo "  stop    - Stop all services"
        echo ""
        echo "Example: $0 podman"
        exit 1
        ;;
esac