#!/bin/bash
# Safe Texas Hold'em LUT generation with resume capability

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "   TEXAS HOLD'EM LUT GENERATION (SAFE)"
echo "   With automatic resume on crash"
echo "==========================================${NC}"
echo ""

# Check for existing progress
check_existing_progress() {
    if [ -f "card_info_lut.joblib" ]; then
        echo -e "${YELLOW}Found existing card_info_lut.joblib${NC}"
        
        # Check which stages are complete using Python
        COMPLETED_STAGES=$(python3 -c "
import joblib
import sys
try:
    lut = joblib.load('card_info_lut.joblib')
    if isinstance(lut, dict):
        print(' '.join(lut.keys()))
    else:
        print('ERROR')
except:
    print('ERROR')
" 2>/dev/null || echo "ERROR")
        
        if [ "$COMPLETED_STAGES" != "ERROR" ] && [ -n "$COMPLETED_STAGES" ]; then
            echo -e "${GREEN}Completed stages: $COMPLETED_STAGES${NC}"
            
            # Check if all stages are complete
            if [[ "$COMPLETED_STAGES" == *"pre_flop"* ]] && \
               [[ "$COMPLETED_STAGES" == *"river"* ]] && \
               [[ "$COMPLETED_STAGES" == *"turn"* ]] && \
               [[ "$COMPLETED_STAGES" == *"flop"* ]]; then
                echo -e "${GREEN}✅ All stages already completed!${NC}"
                echo "To regenerate, delete card_info_lut.joblib first"
                exit 0
            else
                echo -e "${YELLOW}Some stages incomplete. Will resume...${NC}"
                return 0
            fi
        else
            echo -e "${YELLOW}File exists but cannot be read. Will backup and restart.${NC}"
            return 1
        fi
    else
        echo "No existing progress found. Starting fresh."
        return 2
    fi
}

# Parse command line arguments
MODE="${1:-standard}"
ACTION="${2:-generate}"  # generate or resume

if [ "$ACTION" == "status" ]; then
    echo -e "${BLUE}Checking LUT generation status...${NC}"
    check_existing_progress
    exit 0
fi

# Backup function
backup_existing_files() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    
    if [ -f "card_info_lut.joblib" ]; then
        BACKUP_NAME="card_info_lut_${TIMESTAMP}.joblib.bak"
        echo "Backing up existing LUT to $BACKUP_NAME"
        cp card_info_lut.joblib "$BACKUP_NAME"
    fi
    
    if [ -f "centroids.joblib" ]; then
        BACKUP_NAME="centroids_${TIMESTAMP}.joblib.bak"
        echo "Backing up existing centroids to $BACKUP_NAME"
        cp centroids.joblib "$BACKUP_NAME"
    fi
    
    # Backup checkpoint files
    for checkpoint in checkpoint_*.joblib; do
        if [ -f "$checkpoint" ]; then
            cp "$checkpoint" "${checkpoint}.${TIMESTAMP}.bak"
        fi
    done
}

# Set parameters based on mode
case $MODE in
    test)
        echo -e "${YELLOW}Mode: TEST (Fast, lower quality)${NC}"
        RIVER_CLUSTERS=50
        TURN_CLUSTERS=50
        FLOP_CLUSTERS=50
        RIVER_SIM=5
        TURN_SIM=5
        FLOP_SIM=5
        ;;
    standard)
        echo -e "${GREEN}Mode: STANDARD (Balanced)${NC}"
        RIVER_CLUSTERS=200
        TURN_CLUSTERS=200
        FLOP_CLUSTERS=200
        RIVER_SIM=10
        TURN_SIM=10
        FLOP_SIM=10
        ;;
    high)
        echo -e "${GREEN}Mode: HIGH QUALITY${NC}"
        RIVER_CLUSTERS=500
        TURN_CLUSTERS=500
        FLOP_CLUSTERS=500
        RIVER_SIM=20
        TURN_SIM=20
        FLOP_SIM=20
        ;;
    *)
        echo -e "${RED}Unknown mode: $MODE${NC}"
        echo "Usage: $0 [test|standard|high] [generate|resume|status]"
        exit 1
        ;;
esac

# Check for existing progress
check_existing_progress
RESUME_STATUS=$?

if [ $RESUME_STATUS -eq 0 ]; then
    echo -e "${GREEN}Resuming from existing progress...${NC}"
    echo "Stages already complete will be skipped automatically."
elif [ $RESUME_STATUS -eq 1 ]; then
    echo -e "${YELLOW}Backing up corrupted file and starting fresh...${NC}"
    backup_existing_files
    rm -f card_info_lut.joblib centroids.joblib
else
    echo -e "${GREEN}Starting fresh generation...${NC}"
fi

echo ""
echo "Configuration:"
echo "  - Cards: 2-14 (Full 52-card deck)"
echo "  - River clusters: $RIVER_CLUSTERS"
echo "  - Turn clusters: $TURN_CLUSTERS"
echo "  - Flop clusters: $FLOP_CLUSTERS"
echo "  - Simulations: $RIVER_SIM/$TURN_SIM/$FLOP_SIM"
echo ""
echo -e "${YELLOW}Starting in 5 seconds... (Press Ctrl+C to cancel)${NC}"
sleep 5

# Function to run clustering with automatic retry
run_clustering_with_retry() {
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        echo ""
        echo -e "${BLUE}Attempt $attempt of $max_attempts${NC}"
        
        # Start timing
        START_TIME=$(date +%s)
        
        # Run clustering
        if uv run poker_ai cluster \
            --low_card_rank 2 \
            --high_card_rank 14 \
            --n_river_clusters $RIVER_CLUSTERS \
            --n_turn_clusters $TURN_CLUSTERS \
            --n_flop_clusters $FLOP_CLUSTERS \
            --n_simulations_river $RIVER_SIM \
            --n_simulations_turn $TURN_SIM \
            --n_simulations_flop $FLOP_SIM \
            --save_dir .; then
            
            # Success!
            END_TIME=$(date +%s)
            ELAPSED=$((END_TIME - START_TIME))
            HOURS=$((ELAPSED / 3600))
            MINUTES=$(((ELAPSED % 3600) / 60))
            SECONDS=$((ELAPSED % 60))
            
            echo ""
            echo -e "${GREEN}=========================================="
            echo "✅ LUT GENERATION COMPLETE!"
            echo "==========================================${NC}"
            echo ""
            echo "Time taken: ${HOURS}h ${MINUTES}m ${SECONDS}s"
            
            # Check and report file sizes
            if [ -f "card_info_lut.joblib" ]; then
                SIZE=$(ls -lh card_info_lut.joblib | awk '{print $5}')
                echo "Generated file: card_info_lut.joblib"
                echo "Size: $SIZE"
                
                # Create a copy with descriptive name
                cp card_info_lut.joblib "texas_holdem_${MODE}_lut.joblib"
                echo "Also saved as: texas_holdem_${MODE}_lut.joblib"
            fi
            
            if [ -f "centroids.joblib" ]; then
                SIZE=$(ls -lh centroids.joblib | awk '{print $5}')
                echo "Centroids file: centroids.joblib ($SIZE)"
            fi
            
            # List checkpoint files
            echo ""
            echo "Checkpoint files created:"
            ls -lh checkpoint_*.joblib 2>/dev/null || echo "  (No checkpoint files found)"
            
            echo ""
            echo -e "${GREEN}You can now train with full Texas Hold'em!${NC}"
            echo "Use: ./train_ai.sh [mode]"
            
            return 0
        else
            # Failed
            echo ""
            echo -e "${RED}Clustering failed on attempt $attempt${NC}"
            
            if [ $attempt -lt $max_attempts ]; then
                echo -e "${YELLOW}Will retry after checking progress...${NC}"
                sleep 5
                
                # Check what was completed
                check_existing_progress
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Some progress was saved. Retrying to complete remaining stages...${NC}"
                else
                    echo -e "${RED}No valid progress found. Retrying from beginning...${NC}"
                    rm -f card_info_lut.joblib centroids.joblib
                fi
                
                attempt=$((attempt + 1))
            else
                echo -e "${RED}Maximum attempts reached. Generation failed.${NC}"
                echo ""
                echo "Troubleshooting:"
                echo "1. Check available memory (need 8GB+ free)"
                echo "2. Check disk space (need 1GB+ free)"
                echo "3. Try 'test' mode for lower memory usage"
                echo "4. Check for existing checkpoint files:"
                ls -lh checkpoint_*.joblib 2>/dev/null || echo "   No checkpoints found"
                
                return 1
            fi
        fi
    done
}

# Monitor memory usage in background
monitor_resources() {
    while true; do
        if command -v free &> /dev/null; then
            MEM_INFO=$(free -h | grep "^Mem:" | awk '{print "Used: " $3 "/" $2}')
            echo -e "\r${BLUE}Memory: $MEM_INFO${NC}" >&2
        fi
        sleep 30
    done
}

# Start resource monitoring in background
monitor_resources &
MONITOR_PID=$!

# Trap to clean up monitor on exit
trap "kill $MONITOR_PID 2>/dev/null || true" EXIT

# Run the clustering with retry logic
run_clustering_with_retry

# Clean up
kill $MONITOR_PID 2>/dev/null || true