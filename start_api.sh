#!/bin/bash

# Poker AI API Startup Script

echo "======================================"
echo "  Poker AI Web Service Launcher"
echo "======================================"
echo ""

# Parse command line arguments first
MODE=${1:-docker}

# Detect container runtime based on user preference
CONTAINER_RUNTIME=""
COMPOSE_COMMAND=""

# If user explicitly wants docker, check for docker first
if [ "$MODE" = "docker" ] && command -v docker &> /dev/null; then
    CONTAINER_RUNTIME="docker"
    if command -v docker-compose &> /dev/null; then
        COMPOSE_COMMAND="docker-compose"
    fi
elif command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
    if command -v podman-compose &> /dev/null; then
        COMPOSE_COMMAND="podman-compose"
    elif command -v docker-compose &> /dev/null; then
        # Podman can use docker-compose with podman socket
        COMPOSE_COMMAND="docker-compose"
        export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
    else
        echo "⚠️  podman-compose not found. Attempting to install..."
        
        # Try to install podman-compose using uv
        if command -v uv &> /dev/null; then
            echo "Installing podman-compose with uv..."
            # Create a tools venv if it doesn't exist
            if [ ! -d ".venv-tools" ]; then
                uv venv .venv-tools
            fi
            # Install podman-compose in the tools venv
            .venv-tools/bin/pip install podman-compose
            if [ -f ".venv-tools/bin/podman-compose" ]; then
                COMPOSE_COMMAND=".venv-tools/bin/podman-compose"
                echo "✅ podman-compose installed successfully in .venv-tools"
            else
                # Try pipx as alternative
                if command -v pipx &> /dev/null; then
                    echo "Trying pipx..."
                    pipx install podman-compose
                    if command -v podman-compose &> /dev/null; then
                        COMPOSE_COMMAND="podman-compose"
                        echo "✅ podman-compose installed successfully with pipx"
                    fi
                fi
            fi
        elif command -v pip3 &> /dev/null; then
            echo "Installing podman-compose with pip3..."
            pip3 install --user podman-compose
            if [ -f "$HOME/.local/bin/podman-compose" ]; then
                export PATH="$HOME/.local/bin:$PATH"
                COMPOSE_COMMAND="podman-compose"
                echo "✅ podman-compose installed successfully"
            fi
        fi
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
    echo "❌ No compose command found and unable to install."
    echo "Please install manually using one of these methods:"
    echo "  1. pipx install podman-compose  (recommended)"
    echo "  2. pip3 install --user podman-compose"
    echo "  3. brew install podman-compose  (if using Homebrew)"
    echo "  For Docker: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "Using container runtime: $CONTAINER_RUNTIME"
echo "Using compose command: $COMPOSE_COMMAND"
echo ""

case $MODE in
    docker|podman)
        echo "Starting services with $COMPOSE_COMMAND..."
        echo ""
        
        # For Podman, check if the machine is running
        if [ "$CONTAINER_RUNTIME" = "podman" ]; then
            if ! podman system connection list 2>/dev/null | grep -q "true"; then
                echo "⚠️  Podman machine is not running."
                echo ""
                echo "Please start Podman machine first:"
                echo "  podman machine init  (if not already initialized)"
                echo "  podman machine start"
                echo ""
                echo "Or use Docker instead:"
                echo "  ./start_api.sh docker"
                exit 1
            fi
        fi
        
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
        
        # Install dependencies using uv
        if command -v uv &> /dev/null; then
            echo "Using uv to manage dependencies..."
            
            # Ensure project dependencies are installed
            uv sync
            
            # Install API dependencies
            echo "Installing API dependencies..."
            uv pip install -r api/requirements.txt
            
            # Start the API with uv
            echo ""
            echo "Starting API server with uv..."
            uv run uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
        else
            # Fallback to traditional venv
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
        fi
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