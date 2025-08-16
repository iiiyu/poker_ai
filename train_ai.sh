#!/bin/bash
# Convenient training script for poker AI

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
MODE="normal"
ITERATIONS=1000000
PLAYERS=3
SAVE_INTERVAL=10000

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        quick)
            MODE="quick"
            ITERATIONS=10000
            SAVE_INTERVAL=1000
            shift
            ;;
        medium)
            MODE="medium"
            ITERATIONS=100000
            SAVE_INTERVAL=5000
            shift
            ;;
        long)
            MODE="long"
            ITERATIONS=1000000
            SAVE_INTERVAL=10000
            shift
            ;;
        ultra)
            MODE="ultra"
            ITERATIONS=10000000
            SAVE_INTERVAL=50000
            shift
            ;;
        continuous)
            MODE="continuous"
            shift
            ;;
        resume)
            MODE="resume"
            shift
            ;;
        --help)
            echo "Usage: $0 [mode] [options]"
            echo ""
            echo "Modes:"
            echo "  quick       - Quick training (10K iterations, ~5-10 minutes)"
            echo "  medium      - Medium training (100K iterations, ~1-2 hours)"
            echo "  long        - Long training (1M iterations, ~10-20 hours) [default]"
            echo "  ultra       - Ultra long training (10M iterations, ~4-7 days)"
            echo "  continuous  - Continuous training loop (runs indefinitely)"
            echo "  resume      - Resume from latest checkpoint"
            echo ""
            echo "Options:"
            echo "  --players N  - Number of players (2-6, default: 3)"
            echo "  --help       - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 quick           # Quick test training"
            echo "  $0 long            # Standard long training"
            echo "  $0 continuous      # Train indefinitely"
            echo "  $0 resume          # Continue from last checkpoint"
            exit 0
            ;;
        --players)
            PLAYERS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to format time
format_time() {
    local seconds=$1
    if [ $seconds -lt 60 ]; then
        echo "${seconds} seconds"
    elif [ $seconds -lt 3600 ]; then
        echo "$((seconds/60)) minutes"
    elif [ $seconds -lt 86400 ]; then
        echo "$((seconds/3600)) hours"
    else
        echo "$((seconds/86400)) days"
    fi
}

# Estimate training time (rough estimates)
estimate_time() {
    local iters=$1
    # Rough estimate: ~100 iterations per second on modern hardware
    local seconds=$((iters / 100))
    format_time $seconds
}

# Print banner
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           POKER AI TRAINING SYSTEM                    ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

# Check Python environment
echo -e "${YELLOW}Checking environment...${NC}"
if ! command -v uv &> /dev/null; then
    echo -e "${RED}Error: uv is not installed${NC}"
    echo "Please install uv first: https://github.com/astral-sh/uv"
    exit 1
fi

# Display training configuration
echo -e "${GREEN}Training Configuration:${NC}"
echo "  Mode: $MODE"
echo "  Players: $PLAYERS"

case $MODE in
    quick)
        echo "  Iterations: 10,000"
        echo "  Estimated time: ~$(estimate_time 10000)"
        echo "  Purpose: Quick test to verify setup"
        ;;
    medium)
        echo "  Iterations: 100,000"
        echo "  Estimated time: ~$(estimate_time 100000)"
        echo "  Purpose: Basic strategy development"
        ;;
    long)
        echo "  Iterations: 1,000,000"
        echo "  Estimated time: ~$(estimate_time 1000000)"
        echo "  Purpose: Competitive strategy"
        ;;
    ultra)
        echo "  Iterations: 10,000,000"
        echo "  Estimated time: ~$(estimate_time 10000000)"
        echo "  Purpose: Professional-level strategy"
        ;;
    continuous)
        echo "  Iterations: Unlimited (100K per cycle)"
        echo "  Estimated time: Runs until stopped"
        echo "  Purpose: Maximum strength training"
        ;;
    resume)
        echo "  Iterations: Continuing from checkpoint"
        echo "  Purpose: Resume interrupted training"
        ;;
esac

echo ""
echo -e "${YELLOW}Starting in 3 seconds... (Press Ctrl+C to cancel)${NC}"
sleep 3

# Run the appropriate training command
case $MODE in
    quick)
        echo -e "${GREEN}Starting quick training...${NC}"
        python train_long_ai.py \
            --iterations 10000 \
            --players $PLAYERS \
            --save_interval 1000
        ;;
    medium)
        echo -e "${GREEN}Starting medium training...${NC}"
        python train_long_ai.py \
            --iterations 100000 \
            --players $PLAYERS \
            --save_interval 5000
        ;;
    long)
        echo -e "${GREEN}Starting long training...${NC}"
        python train_long_ai.py \
            --iterations 1000000 \
            --players $PLAYERS \
            --save_interval 10000
        ;;
    ultra)
        echo -e "${GREEN}Starting ultra long training...${NC}"
        echo -e "${YELLOW}This will take several days. Make sure your computer won't sleep.${NC}"
        python train_long_ai.py \
            --iterations 10000000 \
            --players $PLAYERS \
            --save_interval 50000
        ;;
    continuous)
        echo -e "${GREEN}Starting continuous training loop...${NC}"
        echo -e "${YELLOW}This will run indefinitely. Press Ctrl+C to stop.${NC}"
        python train_long_ai.py \
            --loop \
            --loop_iterations 100000 \
            --players $PLAYERS \
            --save_interval 10000
        ;;
    resume)
        echo -e "${GREEN}Resuming from latest checkpoint...${NC}"
        python train_long_ai.py \
            --resume \
            --iterations 1000000 \
            --players $PLAYERS \
            --save_interval 10000
        ;;
esac

# Check exit status
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Training completed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    # Find the latest strategy file
    LATEST_STRATEGY=$(ls -t **/offline_strategy*.gz 2>/dev/null | head -1)
    if [ -n "$LATEST_STRATEGY" ]; then
        echo ""
        echo -e "${GREEN}Strategy saved to: $LATEST_STRATEGY${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Test against Slumbot:"
        echo "   uv run test_slumbot.py --strategy_path $LATEST_STRATEGY"
        echo ""
        echo "2. Play against your AI:"
        echo "   uv run poker_ai play --agent offline --strategy_path $LATEST_STRATEGY"
        echo ""
        echo "3. Continue training:"
        echo "   ./train_ai.sh resume"
    fi
else
    echo ""
    echo -e "${YELLOW}Training was interrupted or encountered an error.${NC}"
    echo "You can resume training with: ./train_ai.sh resume"
fi