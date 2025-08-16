#!/bin/bash

# Script to play against your trained poker AI agent

echo "======================================"
echo "  Play Against Your Poker AI"
echo "======================================"
echo ""

# Find the most recent agent
LATEST_AGENT=$(ls -td quick_test_agent_* 2>/dev/null | head -1)

if [ -z "$LATEST_AGENT" ]; then
    echo "❌ No trained agent found!"
    echo ""
    echo "First train an agent with:"
    echo "  ./quick_train.sh quick"
    exit 1
fi

# Check if agent.joblib exists
if [ ! -f "$LATEST_AGENT/agent.joblib" ]; then
    echo "⚠️  No agent.joblib found in $LATEST_AGENT"
    echo "Looking for offline strategy files..."
    
    # Find offline strategy file
    STRATEGY_FILE=$(ls -t $LATEST_AGENT/offline_strategy_*.gz 2>/dev/null | head -1)
    
    if [ -z "$STRATEGY_FILE" ]; then
        echo "❌ No strategy files found!"
        echo "Please train an agent first: ./quick_train.sh quick"
        exit 1
    fi
    
    echo "Found strategy: $STRATEGY_FILE"
    STRATEGY_PATH="$STRATEGY_FILE"
else
    STRATEGY_PATH="$LATEST_AGENT/agent.joblib"
    echo "Found agent: $STRATEGY_PATH"
fi

echo ""
echo "Starting poker game..."
echo "Controls:"
echo "  - Type 'f' to fold"
echo "  - Type 'c' to call/check"
echo "  - Type 'r' to raise"
echo "  - Type 'q' to quit"
echo ""

# Run the game
uv run poker_ai play \
    --lut_path . \
    --strategy_path "$STRATEGY_PATH" \
    --agent offline \
    --pickle_dir False \
    --no_debug_quick_start