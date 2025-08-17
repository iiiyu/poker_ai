#!/bin/bash
# Simple test script to verify LUT generation starts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "   SIMPLE LUT GENERATION TEST"
echo "==========================================${NC}"
echo ""

MODE="${1:-test}"

# Set parameters
case $MODE in
    test)
        echo -e "${YELLOW}Mode: TEST (Fast)${NC}"
        CLUSTERS=50
        SIMS=5
        ;;
    *)
        echo -e "${GREEN}Mode: STANDARD${NC}"
        CLUSTERS=200
        SIMS=10
        ;;
esac

echo ""
echo "Configuration:"
echo "  - Clusters: $CLUSTERS per stage"
echo "  - Simulations: $SIMS per stage"
echo ""

echo -e "${GREEN}Starting generation NOW (no countdown)...${NC}"
echo ""
echo -e "${YELLOW}Running command:${NC}"
echo "uv run poker_ai cluster \\"
echo "    --low_card_rank 2 \\"
echo "    --high_card_rank 14 \\"
echo "    --n_river_clusters $CLUSTERS \\"
echo "    --n_turn_clusters $CLUSTERS \\"
echo "    --n_flop_clusters $CLUSTERS \\"
echo "    --n_simulations_river $SIMS \\"
echo "    --n_simulations_turn $SIMS \\"
echo "    --n_simulations_flop $SIMS \\"
echo "    --save_dir ."
echo ""
echo -e "${GREEN}Executing...${NC}"

# Actually run it
uv run poker_ai cluster \
    --low_card_rank 2 \
    --high_card_rank 14 \
    --n_river_clusters $CLUSTERS \
    --n_turn_clusters $CLUSTERS \
    --n_flop_clusters $CLUSTERS \
    --n_simulations_river $SIMS \
    --n_simulations_turn $SIMS \
    --n_simulations_flop $SIMS \
    --save_dir .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Generation completed successfully!${NC}"
else
    echo -e "${RED}❌ Generation failed!${NC}"
fi