#!/bin/bash

# Quick training script for testing the poker AI

echo "======================================"
echo "  Quick Poker AI Training for Testing"
echo "======================================"
echo ""

# Parse arguments
SIZE=${1:-small}
PLAYERS=${2:-2}

case $SIZE in
    quick)
        echo "Training QUICK agent (10 iterations, 2 players)..."
        ITERATIONS=10
        DUMP_ITER=5
        PLAYERS=2
        OUTPUT_DIR="quick_test_agent"
        ;;
    small)
        echo "Training SMALL agent (100 iterations, $PLAYERS players)..."
        ITERATIONS=100
        DUMP_ITER=25
        OUTPUT_DIR="small_test_agent"
        ;;
    medium)
        echo "Training MEDIUM agent (1000 iterations, $PLAYERS players)..."
        ITERATIONS=1000
        DUMP_ITER=100
        OUTPUT_DIR="medium_test_agent"
        ;;
    *)
        echo "Usage: $0 [quick|small|medium] [n_players]"
        echo ""
        echo "Sizes:"
        echo "  quick  - 10 iterations (very fast, ~30 seconds)"
        echo "  small  - 100 iterations (fast, ~5 minutes)"
        echo "  medium - 1000 iterations (moderate, ~30 minutes)"
        echo ""
        echo "Examples:"
        echo "  $0 quick        # Quick 2-player agent"
        echo "  $0 small 4      # Small 4-player agent"
        echo "  $0 medium 6     # Medium 6-player agent"
        exit 1
        ;;
esac

# Create output directory
mkdir -p trained_agents/$OUTPUT_DIR

echo ""
echo "Configuration:"
echo "  - Size: $SIZE"
echo "  - Players: $PLAYERS"
echo "  - Iterations: $ITERATIONS"
echo "  - Output: trained_agents/$OUTPUT_DIR"
echo ""

# Run training using uv
echo "Starting training..."
echo "This may take a while. Press Ctrl+C to cancel."
echo ""

uv run poker_ai train start \
    --n_players $PLAYERS \
    --n_iterations $ITERATIONS \
    --dump_iteration $DUMP_ITER \
    --nickname $OUTPUT_DIR \
    --pickle_dir False \
    --single_process

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Training completed successfully!"
    echo ""
    
    # Find the actual output directory (includes timestamp)
    ACTUAL_DIR=$(ls -td ${OUTPUT_DIR}_* 2>/dev/null | head -1)
    if [ -n "$ACTUAL_DIR" ]; then
        echo "Agent saved to: $ACTUAL_DIR/"
        
        # Check for agent files
        if [ -f "$ACTUAL_DIR/agent.joblib" ]; then
            AGENT_FILE="$ACTUAL_DIR/agent.joblib"
        else
            AGENT_FILE=$(ls -t $ACTUAL_DIR/offline_strategy_*.gz 2>/dev/null | head -1)
        fi
        
        if [ -n "$AGENT_FILE" ]; then
            echo ""
            echo "To play against your agent:"
            echo "  ./play_agent.sh"
            echo ""
            echo "Or manually:"
            echo "  uv run poker_ai play \\"
            echo "    --lut_path . \\"
            echo "    --strategy_path $AGENT_FILE \\"
            echo "    --agent offline \\"
            echo "    --pickle_dir False"
        fi
    else
        echo "Agent saved to: ${OUTPUT_DIR}_*/"
        echo ""
        echo "To play against your agent:"
        echo "  ./play_agent.sh"
    fi
else
    echo ""
    echo "❌ Training failed. Check the error messages above."
    exit 1
fi