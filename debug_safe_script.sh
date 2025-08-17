#!/bin/bash
# Debug version of the safe script to trace execution

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "   DEBUG SAFE SCRIPT"
echo "==========================================${NC}"
echo ""

echo "1. Script started"

MODE="${1:-test}"
echo "2. MODE set to: $MODE"

# Simple function that returns 2
test_function() {
    echo "   Inside function"
    return 2
}

echo "3. Calling test function..."
test_function || RESULT=$?
RESULT=${RESULT:-0}
echo "4. Function returned: $RESULT"

echo "5. Continuing after function..."

if [ $RESULT -eq 2 ]; then
    echo "6. Result was 2, handling it..."
fi

echo "7. Setting parameters..."
CLUSTERS=50
SIMS=5

echo "8. Showing configuration..."
echo "   Clusters: $CLUSTERS"
echo "   Simulations: $SIMS"

echo "9. About to sleep..."
echo -e "${YELLOW}Starting in 3 seconds...${NC}"
sleep 3

echo "10. After sleep, about to run command..."

echo -e "${GREEN}Would run: uv run poker_ai cluster --low_card_rank 2 --high_card_rank 14${NC}"

echo "11. Script completed successfully!"
echo ""
echo -e "${GREEN}If you see all 11 steps, the script flow is working correctly.${NC}"
echo -e "${YELLOW}If it stops before step 11, we know where the issue is.${NC}"