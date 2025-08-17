#!/bin/bash
# Generate Texas Hold'em card info LUT (52 cards) with optimized settings

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "   TEXAS HOLD'EM LUT GENERATION"
echo "==========================================${NC}"
echo ""
echo "This will generate a complete LUT for 52-card Texas Hold'em."
echo ""

# Parse command line arguments
MODE="${1:-standard}"

case $MODE in
    test)
        echo -e "${YELLOW}Mode: TEST (Fast, lower quality)${NC}"
        echo "  - Cards: 2-14 (Full 52-card deck)"
        echo "  - Clusters: 50 each (minimal)"
        echo "  - Simulations: 5 each (fast)"
        echo "  - Estimated time: 30-60 minutes"
        echo "  - Expected size: ~150-200MB"
        RIVER_CLUSTERS=50
        TURN_CLUSTERS=50
        FLOP_CLUSTERS=50
        RIVER_SIM=5
        TURN_SIM=5
        FLOP_SIM=5
        ;;
    standard)
        echo -e "${GREEN}Mode: STANDARD (Balanced)${NC}"
        echo "  - Cards: 2-14 (Full 52-card deck)"
        echo "  - Clusters: 200 each"
        echo "  - Simulations: 10 each"
        echo "  - Estimated time: 2-4 hours"
        echo "  - Expected size: ~300-400MB"
        RIVER_CLUSTERS=200
        TURN_CLUSTERS=200
        FLOP_CLUSTERS=200
        RIVER_SIM=10
        TURN_SIM=10
        FLOP_SIM=10
        ;;
    high)
        echo -e "${GREEN}Mode: HIGH QUALITY${NC}"
        echo "  - Cards: 2-14 (Full 52-card deck)"
        echo "  - Clusters: 500 each"
        echo "  - Simulations: 20 each"
        echo "  - Estimated time: 6-10 hours"
        echo "  - Expected size: ~500-700MB"
        RIVER_CLUSTERS=500
        TURN_CLUSTERS=500
        FLOP_CLUSTERS=500
        RIVER_SIM=20
        TURN_SIM=20
        FLOP_SIM=20
        ;;
    *)
        echo -e "${RED}Unknown mode: $MODE${NC}"
        echo "Usage: $0 [test|standard|high]"
        echo "  test     - Fast generation for testing"
        echo "  standard - Balanced quality/speed (default)"
        echo "  high     - High quality, slow"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}⚠️  This will overwrite existing LUT files!${NC}"
echo "Starting in 5 seconds... (Press Ctrl+C to cancel)"
sleep 5

# Backup existing LUTs
if [ -f "card_info_lut.joblib" ]; then
    BACKUP_NAME="card_info_lut_$(date +%Y%m%d_%H%M%S).joblib.bak"
    echo "Backing up existing LUT to $BACKUP_NAME"
    mv card_info_lut.joblib "$BACKUP_NAME"
fi

if [ -f "texas_holdem_card_info_lut.joblib" ]; then
    BACKUP_NAME="texas_holdem_card_info_lut_$(date +%Y%m%d_%H%M%S).joblib.bak"
    echo "Backing up existing Texas Hold'em LUT to $BACKUP_NAME"
    mv texas_holdem_card_info_lut.joblib "$BACKUP_NAME"
fi

# Start timing
START_TIME=$(date +%s)

echo ""
echo -e "${GREEN}Starting clustering process...${NC}"
echo "This will process:"
echo "  - River: ~133 million combinations"
echo "  - Turn: ~20 million combinations"
echo "  - Flop: ~2.6 million combinations"
echo ""

# Run clustering with full deck parameters
uv run poker_ai cluster \
    --low_card_rank 2 \
    --high_card_rank 14 \
    --n_river_clusters $RIVER_CLUSTERS \
    --n_turn_clusters $TURN_CLUSTERS \
    --n_flop_clusters $FLOP_CLUSTERS \
    --n_simulations_river $RIVER_SIM \
    --n_simulations_turn $TURN_SIM \
    --n_simulations_flop $FLOP_SIM \
    --save_dir .

# Calculate elapsed time
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
    
    # Also create a copy with descriptive name
    cp card_info_lut.joblib "texas_holdem_${MODE}_lut.joblib"
    echo "Also saved as: texas_holdem_${MODE}_lut.joblib"
else
    echo -e "${RED}Error: LUT file not generated!${NC}"
    exit 1
fi

if [ -f "centroids.joblib" ]; then
    SIZE=$(ls -lh centroids.joblib | awk '{print $5}')
    echo "Centroids file: centroids.joblib ($SIZE)"
fi

echo ""
echo -e "${GREEN}You can now train with full Texas Hold'em!${NC}"
echo "Use: ./train_ai.sh [mode]"