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
    # Debug: Show current directory and any .joblib files
    echo -e "${BLUE}Checking directory: $(pwd)${NC}"
    
    # Quick check for any .joblib files
    local joblib_count=$(ls -1 *.joblib 2>/dev/null | wc -l)
    if [ $joblib_count -gt 0 ]; then
        echo -e "${BLUE}Found $joblib_count .joblib file(s) in directory:${NC}"
        # List the actual files found
        for f in *.joblib; do
            if [ -f "$f" ]; then
                local size=$(ls -lh "$f" | awk '{print $5}')
                echo -e "${BLUE}  - $f (${size})${NC}"
            fi
        done
    fi
    
    # First check for any existing LUT files or checkpoints
    local found_files=0
    local lut_file=""
    
    # Check for main LUT file
    if [ -f "card_info_lut.joblib" ]; then
        lut_file="card_info_lut.joblib"
        echo -e "${YELLOW}Found existing card_info_lut.joblib${NC}"
        found_files=1
    else
        echo -e "${BLUE}No main LUT file (card_info_lut.joblib) found${NC}"
    fi
    
    # Check for descriptive LUT files
    # Use nullglob to handle no matches properly
    shopt -s nullglob
    texas_files=(texas_holdem_*_lut.joblib)
    shopt -u nullglob
    
    if [ ${#texas_files[@]} -eq 0 ]; then
        echo -e "${BLUE}No descriptive LUT files (texas_holdem_*_lut.joblib) found${NC}"
    else
        for file in "${texas_files[@]}"; do
            if [ -f "$file" ]; then
                echo -e "${YELLOW}Found existing LUT: $file${NC}"
                found_files=1
                # If no main file, could use this one
                if [ -z "$lut_file" ]; then
                    echo -e "${BLUE}Could restore from: $file${NC}"
                    echo -e "${BLUE}Run: cp $file card_info_lut.joblib${NC}"
                fi
            fi
        done
    fi
    
    # Check for checkpoint files
    shopt -s nullglob
    checkpoint_files=(checkpoint_*.joblib)
    shopt -u nullglob
    
    if [ ${#checkpoint_files[@]} -eq 0 ]; then
        echo -e "${BLUE}No checkpoint files (checkpoint_*.joblib) found${NC}"
    else
        for checkpoint in "${checkpoint_files[@]}"; do
            if [ -f "$checkpoint" ]; then
                echo -e "${YELLOW}Found checkpoint: $checkpoint${NC}"
                found_files=1
                # Extract stage name from checkpoint
                stage=$(echo $checkpoint | sed 's/checkpoint_\(.*\)\.joblib/\1/')
                echo -e "${BLUE}  Stage completed: $stage${NC}"
            fi
        done
    fi
    
    # If we have the main LUT file, check its contents
    if [ -f "card_info_lut.joblib" ]; then
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
            echo -e "${GREEN}Completed stages in main file: $COMPLETED_STAGES${NC}"
            
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
            echo -e "${YELLOW}Main file exists but cannot be read. Will backup and restart.${NC}"
            return 1
        fi
    elif [ $found_files -eq 1 ]; then
        # We found some files but no main LUT
        echo -e "${YELLOW}Found existing work but no main card_info_lut.joblib${NC}"
        echo -e "${YELLOW}You may want to restore from a backup or checkpoint${NC}"
        echo ""
        echo "Options:"
        echo "1. Start fresh (current choice)"
        echo "2. Restore from backup: cp texas_holdem_*_lut.joblib card_info_lut.joblib"
        echo "3. Use checkpoints (if complete enough)"
        echo ""
        echo -e "${BLUE}Starting fresh in 10 seconds... (Ctrl+C to cancel and restore manually)${NC}"
        sleep 10
        return 2
    else
        # Check if there are any .joblib files that don't match our patterns
        if [ $joblib_count -gt 0 ]; then
            echo -e "${YELLOW}Found .joblib file(s) but they don't match expected patterns.${NC}"
            echo -e "${YELLOW}Expected patterns:${NC}"
            echo "  - card_info_lut.joblib (main file)"
            echo "  - texas_holdem_*_lut.joblib (descriptive names)"
            echo "  - checkpoint_*.joblib (checkpoints)"
            echo ""
            echo -e "${YELLOW}Possible actions:${NC}"
            # Check if any file might be a LUT based on size
            for f in *.joblib; do
                if [ -f "$f" ]; then
                    local size_bytes=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
                    local size_mb=$((size_bytes / 1048576))
                    if [ $size_mb -gt 50 ]; then
                        echo -e "${GREEN}  File '$f' is ${size_mb}MB - likely a LUT file${NC}"
                        echo -e "${GREEN}  Try: mv '$f' card_info_lut.joblib${NC}"
                    else
                        echo -e "${BLUE}  File '$f' is ${size_mb}MB - probably not a LUT${NC}"
                    fi
                fi
            done
            echo ""
            echo -e "${BLUE}Starting fresh in 10 seconds... (Ctrl+C to rename files first)${NC}"
            sleep 10
        else
            echo -e "${GREEN}No existing work found. Starting fresh generation.${NC}"
        fi
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
echo -e "${YELLOW}Starting generation in 5 seconds... (Press Ctrl+C to cancel)${NC}"
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