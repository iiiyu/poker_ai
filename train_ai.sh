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
USE_MULTIPROCESS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        test)
            MODE="test"
            ITERATIONS=100
            SAVE_INTERVAL=50
            shift
            ;;
        quick)
            MODE="quick"
            ITERATIONS=1000
            SAVE_INTERVAL=200
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
            echo "  test        - Test training (100 iterations, ~30 seconds)"
            echo "  quick       - Quick training (1K iterations, ~2-5 minutes)"
            echo "  medium      - Medium training (100K iterations, ~3-8 hours)"
            echo "  long        - Long training (1M iterations, ~30-80 hours) [default]"
            echo "  ultra       - Ultra long training (10M iterations, ~2-4 weeks)"
            echo "  continuous  - Continuous training loop (runs indefinitely)"
            echo "  resume      - Resume from latest checkpoint"
            echo ""
            echo "Options:"
            echo "  --players N  - Number of players (2-6, default: 3)"
            echo "  --multi      - Use multiprocessing for faster training"
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
        --multi)
            USE_MULTIPROCESS=true
            shift
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
    local players=$2
    local multiprocess=$3
    
    # More realistic estimates based on actual performance
    # Single process: ~5-15 iterations/second
    # Multi process: ~20-50 iterations/second
    # Scales with number of players
    
    if [ "$multiprocess" = true ]; then
        local rate=30  # Average for multiprocess
    else
        local rate=10  # Average for single process
    fi
    
    # Adjust for number of players (more players = slower)
    rate=$((rate * 3 / players))
    
    local seconds=$((iters / rate))
    local min_seconds=$((seconds * 3 / 4))  # -25% for best case
    local max_seconds=$((seconds * 3 / 2))  # +50% for worst case
    
    echo "$(format_time $min_seconds) - $(format_time $max_seconds)"
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
if [ "$USE_MULTIPROCESS" = true ]; then
    echo "  Processing: Multiprocess (faster)"
else
    echo "  Processing: Single process"
fi

case $MODE in
    test)
        echo "  Iterations: 100"
        echo "  Estimated time: $(estimate_time 100 $PLAYERS $USE_MULTIPROCESS)"
        echo "  Purpose: Minimal test to verify setup works"
        ;;
    quick)
        echo "  Iterations: 1,000"
        echo "  Estimated time: $(estimate_time 1000 $PLAYERS $USE_MULTIPROCESS)"
        echo "  Purpose: Quick training for basic strategy"
        ;;
    medium)
        echo "  Iterations: 100,000"
        echo "  Estimated time: $(estimate_time 100000 $PLAYERS $USE_MULTIPROCESS)"
        echo "  Purpose: Decent strategy development"
        ;;
    long)
        echo "  Iterations: 1,000,000"
        echo "  Estimated time: $(estimate_time 1000000 $PLAYERS $USE_MULTIPROCESS)"
        echo "  Purpose: Strong competitive strategy"
        ;;
    ultra)
        echo "  Iterations: 10,000,000"
        echo "  Estimated time: $(estimate_time 10000000 $PLAYERS $USE_MULTIPROCESS)"
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
    test)
        echo -e "${GREEN}Starting test training (100 iterations)...${NC}"
        if [ "$USE_MULTIPROCESS" = true ]; then
            python train_long_ai.py \
                --iterations 100 \
                --players $PLAYERS \
                --save_interval 50
        else
            python train_long_ai.py \
                --iterations 100 \
                --players $PLAYERS \
                --save_interval 50 \
                --single_process
        fi
        ;;
    quick)
        echo -e "${GREEN}Starting quick training (1K iterations)...${NC}"
        if [ "$USE_MULTIPROCESS" = true ]; then
            python train_long_ai.py \
                --iterations 1000 \
                --players $PLAYERS \
                --save_interval 200
        else
            python train_long_ai.py \
                --iterations 1000 \
                --players $PLAYERS \
                --save_interval 200 \
                --single_process
        fi
        ;;
    medium)
        echo -e "${GREEN}Starting medium training...${NC}"
        if [ "$USE_MULTIPROCESS" = true ]; then
            python train_long_ai.py \
                --iterations 100000 \
                --players $PLAYERS \
                --save_interval 5000
        else
            python train_long_ai.py \
                --iterations 100000 \
                --players $PLAYERS \
                --save_interval 5000 \
                --single_process
        fi
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