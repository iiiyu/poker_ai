#!/bin/bash
# Unified SQLite-backed LUT generation script
# Uses database backing for ALL stages to prevent memory issues

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================="
echo "   UNIFIED SQLite LUT GENERATION"
echo "   Database-backed for all stages"
echo "==========================================${NC}"
echo ""

# Function to get available memory in GB
get_available_memory_gb() {
    if command -v free &> /dev/null; then
        # Linux
        free -g | awk '/^Mem:/{print $7}'
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - Get free + inactive memory
        local page_size=$(pagesize)
        local free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local inactive_pages=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local purgeable_pages=$(vm_stat | grep "Pages purgeable" | awk '{print $3}' | sed 's/\.//')
        # Calculate available memory
        echo $(( (free_pages + inactive_pages + purgeable_pages) * page_size / 1024 / 1024 / 1024 ))
    else
        echo "0"
    fi
}

# Function to get total memory in GB
get_total_memory_gb() {
    if command -v free &> /dev/null; then
        # Linux
        free -g | awk '/^Mem:/{print $2}'
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo $(($(sysctl -n hw.memsize)/1024/1024/1024))
    else
        echo "0"
    fi
}

# Show system info
echo -e "${BLUE}=== System Information ===${NC}"
TOTAL_MEM=$(get_total_memory_gb)
AVAIL_MEM=$(get_available_memory_gb)
echo "Total memory: ${TOTAL_MEM}GB"
echo "Available memory: ${AVAIL_MEM}GB"
echo ""

# Parse mode
MODE="${1:-auto}"

# Auto-detect optimal settings based on available memory
if [ "$MODE" == "auto" ]; then
    if [ $AVAIL_MEM -ge 50 ]; then
        MODE="ultra"
    elif [ $AVAIL_MEM -ge 40 ]; then
        MODE="high"
    elif [ $AVAIL_MEM -ge 20 ]; then
        MODE="medium"
    elif [ $AVAIL_MEM -ge 10 ]; then
        MODE="low"
    else
        MODE="minimal"
    fi
    echo -e "${GREEN}Auto-selected mode: $MODE (based on ${AVAIL_MEM}GB available)${NC}"
fi

# Configuration based on mode
case $MODE in
    minimal)
        echo -e "${RED}Mode: MINIMAL (5GB memory usage)${NC}"
        RIVER_CLUSTERS=50
        TURN_CLUSTERS=50
        FLOP_CLUSTERS=50
        SIMULATIONS=2
        MEMORY_LIMIT=5
        BATCH_SIZE=20
        ;;
    low)
        echo -e "${YELLOW}Mode: LOW (8GB memory usage)${NC}"
        RIVER_CLUSTERS=100
        TURN_CLUSTERS=75
        FLOP_CLUSTERS=75
        SIMULATIONS=3
        MEMORY_LIMIT=8
        BATCH_SIZE=30
        ;;
    medium)
        echo -e "${GREEN}Mode: MEDIUM (20GB memory usage)${NC}"
        RIVER_CLUSTERS=150
        TURN_CLUSTERS=100
        FLOP_CLUSTERS=100
        SIMULATIONS=8
        MEMORY_LIMIT=20
        BATCH_SIZE=50
        ;;
    high)
        echo -e "${GREEN}Mode: HIGH (45GB memory usage)${NC}"
        RIVER_CLUSTERS=300
        TURN_CLUSTERS=200
        FLOP_CLUSTERS=200
        SIMULATIONS=15
        MEMORY_LIMIT=45
        BATCH_SIZE=50
        ;;
    ultra)
        echo -e "${CYAN}Mode: ULTRA (50GB memory usage)${NC}"
        echo -e "${CYAN}Optimized for your 63GB system${NC}"
        RIVER_CLUSTERS=400
        TURN_CLUSTERS=300
        FLOP_CLUSTERS=300
        SIMULATIONS=20
        MEMORY_LIMIT=50
        BATCH_SIZE=50
        ;;
    custom)
        echo -e "${BLUE}Mode: CUSTOM${NC}"
        RIVER_CLUSTERS="${2:-200}"
        TURN_CLUSTERS="${3:-200}"
        FLOP_CLUSTERS="${4:-200}"
        SIMULATIONS="${5:-10}"
        MEMORY_LIMIT="${6:-50}"
        BATCH_SIZE="${7:-50}"
        ;;
    *)
        echo -e "${RED}Unknown mode: $MODE${NC}"
        echo "Usage: $0 [minimal|low|medium|high|ultra|custom] [river_clusters] [turn_clusters] [flop_clusters] [simulations] [memory_limit] [batch_size]"
        echo ""
        echo "Examples:"
        echo "  $0 auto              # Auto-detect based on available memory"
        echo "  $0 minimal           # Use minimal settings (5GB)"
        echo "  $0 ultra             # Use ultra settings (50GB)"
        echo "  $0 custom 300 200 200 15 45 50  # Custom settings"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=== Configuration ===${NC}"
echo "River clusters: $RIVER_CLUSTERS"
echo "Turn clusters: $TURN_CLUSTERS"
echo "Flop clusters: $FLOP_CLUSTERS"
echo "Simulations: $SIMULATIONS"
echo "Memory limit: ${MEMORY_LIMIT}GB"
echo "Batch size: $BATCH_SIZE"
echo ""

# Check for existing database
DB_PATH="clustering_data.db"
CHECKPOINT_DIR="lut_checkpoints"

if [ -f "$DB_PATH" ]; then
    DB_SIZE=$(ls -lh $DB_PATH | awk '{print $5}')
    echo -e "${YELLOW}Found existing database: $DB_PATH ($DB_SIZE)${NC}"
    echo "Will resume from checkpoints if available"
fi

if [ -d "$CHECKPOINT_DIR" ]; then
    CHECKPOINT_COUNT=$(ls -1 $CHECKPOINT_DIR/*.joblib 2>/dev/null | wc -l)
    if [ $CHECKPOINT_COUNT -gt 0 ]; then
        echo -e "${GREEN}Found $CHECKPOINT_COUNT checkpoint files${NC}"
    fi
fi
echo ""

# Safety check
if [ $MEMORY_LIMIT -gt $AVAIL_MEM ]; then
    echo -e "${RED}WARNING: Requested memory (${MEMORY_LIMIT}GB) exceeds available (${AVAIL_MEM}GB)${NC}"
    echo -e "${YELLOW}Continue anyway? (y/n)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo -e "${YELLOW}Starting generation in 5 seconds... (Ctrl+C to cancel)${NC}"
sleep 5

echo ""
echo -e "${GREEN}Running unified SQLite-backed LUT builder...${NC}"
echo ""

# Run the unified builder
python3 -c "
import sys
import os
sys.path.insert(0, '.')

from poker_ai.clustering.unified_sqlite_builder import UnifiedSQLiteLUTBuilder

print('Initializing unified SQLite builder...')

builder = UnifiedSQLiteLUTBuilder(
    n_simulations_river=${SIMULATIONS},
    n_simulations_turn=${SIMULATIONS},
    n_simulations_flop=${SIMULATIONS},
    low_card_rank=2,
    high_card_rank=14,
    save_dir='.',
    n_river_clusters=${RIVER_CLUSTERS},
    n_turn_clusters=${TURN_CLUSTERS},
    n_flop_clusters=${FLOP_CLUSTERS},
    memory_limit_gb=${MEMORY_LIMIT},
    batch_size=${BATCH_SIZE},
    db_path='${DB_PATH}',
    checkpoint_dir='${CHECKPOINT_DIR}'
)

print('Starting clustering process...')
builder.compute(
    n_river_clusters=${RIVER_CLUSTERS},
    n_turn_clusters=${TURN_CLUSTERS},
    n_flop_clusters=${FLOP_CLUSTERS}
)

print('Cleaning up...')
builder.cleanup()
print('Done!')
"

RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "✅ LUT GENERATION SUCCESSFUL!"
    echo "==========================================${NC}"
    
    # Show file sizes
    if [ -f "card_info_lut.joblib" ]; then
        SIZE=$(ls -lh card_info_lut.joblib | awk '{print $5}')
        echo "LUT file: card_info_lut.joblib ($SIZE)"
    fi
    
    if [ -f "centroids.joblib" ]; then
        SIZE=$(ls -lh centroids.joblib | awk '{print $5}')
        echo "Centroids: centroids.joblib ($SIZE)"
    fi
    
    if [ -f "$DB_PATH" ]; then
        SIZE=$(ls -lh $DB_PATH | awk '{print $5}')
        echo ""
        echo -e "${YELLOW}Database file: $DB_PATH ($SIZE)${NC}"
        echo "You can delete this file to free disk space:"
        echo "  rm $DB_PATH"
    fi
    
    echo ""
    echo "You can now train with: ./train_ai.sh"
else
    echo ""
    echo -e "${RED}=========================================="
    echo "❌ Generation failed with code $RESULT"
    echo "==========================================${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check memory usage with: free -h"
    echo "2. Try a lower quality mode: $0 low"
    echo "3. Check for Python errors above"
    echo "4. Database allows resuming - just run again"
    
    # Check for database
    if [ -f "$DB_PATH" ]; then
        SIZE=$(ls -lh $DB_PATH | awk '{print $5}')
        echo ""
        echo -e "${YELLOW}Database exists: $DB_PATH ($SIZE)${NC}"
        echo "Progress was saved. Run again to resume."
    fi
fi