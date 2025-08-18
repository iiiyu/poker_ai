#!/bin/bash

# Memory-safe LUT generation script with multiple safety modes
# Designed to work on systems with limited RAM

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_PATH="clustering_data.db"
CHECKPOINT_DIR="lut_checkpoints"
OUTPUT_FILE="card_info_lut.joblib"

# Function to print colored messages
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Function to check available memory
check_memory() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        free -g | awk '/^Mem:/{print $7}'
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        vm_stat | grep "Pages free" | awk '{print int($3*4096/1024/1024/1024)}'
    else
        echo "8"  # Default fallback
    fi
}

# Function to monitor memory during execution
monitor_memory() {
    local pid=$1
    local limit=$2
    
    while kill -0 $pid 2>/dev/null; do
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            mem_usage=$(ps -o rss= -p $pid | awk '{print int($1/1024/1024)}')
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            mem_usage=$(ps -o rss= -p $pid | awk '{print int($1/1024)}')
        fi
        
        if [ ! -z "$mem_usage" ] && [ "$mem_usage" -gt "$((limit * 1024))" ]; then
            print_msg $RED "⚠️  Memory limit exceeded! (${mem_usage}MB > ${limit}GB)"
            kill -TERM $pid 2>/dev/null
            return 1
        fi
        sleep 5
    done
}

# Parse command line arguments
MODE=${1:-auto}

print_msg $BLUE "
==========================================
  Memory-Safe LUT Generator
  Mode: $MODE
==========================================
"

# Check if database exists (resuming)
if [ -f "$DB_PATH" ]; then
    print_msg $YELLOW "Found existing database. Checking progress..."
    
    # Check progress
    PROGRESS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM turn_data WHERE distribution IS NOT NULL" 2>/dev/null || echo "0")
    TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT combo) FROM turn_data" 2>/dev/null || echo "1326")
    
    if [ "$PROGRESS" -gt 0 ]; then
        PERCENT=$((PROGRESS * 100 / TOTAL))
        print_msg $YELLOW "Progress: $PROGRESS/$TOTAL ($PERCENT%)"
        
        if [ "$PERCENT" -ge 98 ] && [ "$MODE" != "finalize" ]; then
            print_msg $YELLOW "Turn processing nearly complete. Switching to recovery mode..."
            MODE="recover"
        fi
    fi
fi

# Detect available memory
AVAILABLE_MEM=$(check_memory)
print_msg $BLUE "Available memory: ${AVAILABLE_MEM}GB"

# Set parameters based on mode
case $MODE in
    emergency)
        print_msg $RED "🚨 EMERGENCY MODE - Minimal memory usage"
        MEMORY_LIMIT=3
        BATCH_SIZE=5
        SIMULATIONS=100
        RIVER_CLUSTERS=10
        TURN_CLUSTERS=50
        FLOP_CLUSTERS=150
        SAFETY_FACTOR=0.5
        CHUNK_SIZE=50
        ;;
    
    safe)
        print_msg $YELLOW "🛡️  SAFE MODE - Conservative memory usage"
        MEMORY_LIMIT=$((AVAILABLE_MEM * 6 / 10))
        BATCH_SIZE=10
        SIMULATIONS=200
        RIVER_CLUSTERS=15
        TURN_CLUSTERS=75
        FLOP_CLUSTERS=200
        SAFETY_FACTOR=0.6
        CHUNK_SIZE=75
        ;;
    
    low)
        print_msg $GREEN "💾 LOW MODE - Reduced quality for faster generation"
        MEMORY_LIMIT=$((AVAILABLE_MEM * 7 / 10))
        BATCH_SIZE=20
        SIMULATIONS=500
        RIVER_CLUSTERS=20
        TURN_CLUSTERS=100
        FLOP_CLUSTERS=250
        SAFETY_FACTOR=0.7
        CHUNK_SIZE=100
        ;;
    
    high)
        print_msg $GREEN "⚡ HIGH MODE - Better quality, more memory"
        MEMORY_LIMIT=$((AVAILABLE_MEM * 8 / 10))
        BATCH_SIZE=50
        SIMULATIONS=2000
        RIVER_CLUSTERS=50
        TURN_CLUSTERS=200
        FLOP_CLUSTERS=500
        SAFETY_FACTOR=0.8
        CHUNK_SIZE=150
        ;;
    
    auto)
        print_msg $BLUE "🤖 AUTO MODE - Selecting based on available memory"
        if [ "$AVAILABLE_MEM" -lt 5 ]; then
            MODE="emergency"
            exec $0 emergency
        elif [ "$AVAILABLE_MEM" -lt 10 ]; then
            MODE="safe"
            exec $0 safe
        elif [ "$AVAILABLE_MEM" -lt 20 ]; then
            MODE="low"
            exec $0 low
        else
            MODE="high"
            exec $0 high
        fi
        ;;
    
    recover)
        print_msg $YELLOW "🔧 RECOVERY MODE - Completing failed generation"
        python3 complete_turn_recovery.py --db "$DB_PATH" --memory 3
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            print_msg $GREEN "✅ Recovery successful! Run with 'finalize' to create LUT file"
        else
            print_msg $RED "❌ Recovery failed. Try 'emergency' mode"
        fi
        exit $exit_code
        ;;
    
    finalize)
        print_msg $BLUE "📦 FINALIZE MODE - Creating LUT file from database"
        python3 -c "
import sys
sys.path.insert(0, '.')
from poker_ai.clustering.memory_safe_builder import MemorySafeUnifiedBuilder

builder = MemorySafeUnifiedBuilder(
    n_simulations_river=100,
    n_simulations_turn=100,
    n_simulations_flop=100,
    low_card_rank=2,
    high_card_rank=14,
    save_dir='.',
    n_river_clusters=10,
    n_turn_clusters=50,
    n_flop_clusters=150,
    memory_limit_gb=3,
    batch_size=1,
    db_path='$DB_PATH',
    checkpoint_dir='$CHECKPOINT_DIR',
    safety_factor=0.5,
    chunk_size=50
)

print('Creating final LUT file...')
builder._save_lut()
print('✅ LUT file created successfully!')
"
        exit $?
        ;;
    
    test)
        print_msg $YELLOW "🧪 TEST MODE - Quick generation for testing"
        MEMORY_LIMIT=2
        BATCH_SIZE=2
        SIMULATIONS=50
        RIVER_CLUSTERS=5
        TURN_CLUSTERS=10
        FLOP_CLUSTERS=20
        SAFETY_FACTOR=0.5
        CHUNK_SIZE=20
        ;;
    
    *)
        print_msg $RED "Unknown mode: $MODE"
        echo "Usage: $0 [emergency|safe|low|high|auto|recover|finalize|test]"
        exit 1
        ;;
esac

# Display configuration
print_msg $BLUE "
Configuration:
- Memory Limit: ${MEMORY_LIMIT}GB
- Batch Size: $BATCH_SIZE
- Simulations: $SIMULATIONS
- River Clusters: $RIVER_CLUSTERS
- Turn Clusters: $TURN_CLUSTERS
- Flop Clusters: $FLOP_CLUSTERS
- Safety Factor: $SAFETY_FACTOR
- Chunk Size: $CHUNK_SIZE
"

# Create checkpoint directory
mkdir -p "$CHECKPOINT_DIR"

# Start generation with memory monitoring
print_msg $GREEN "Starting generation..."

# Run Python script in background
python3 -c "
import sys
import os
sys.path.insert(0, '.')

# Use memory-safe builder
from poker_ai.clustering.memory_safe_builder import MemorySafeUnifiedBuilder

print('Initializing memory-safe builder...')

builder = MemorySafeUnifiedBuilder(
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
    checkpoint_dir='${CHECKPOINT_DIR}',
    safety_factor=${SAFETY_FACTOR},
    chunk_size=${CHUNK_SIZE}
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
" &

PID=$!

# Monitor memory usage
monitor_memory $PID $MEMORY_LIMIT &
MONITOR_PID=$!

# Wait for main process
wait $PID
exit_code=$?

# Kill monitor if still running
kill $MONITOR_PID 2>/dev/null || true

# Check exit status
if [ $exit_code -eq 0 ]; then
    print_msg $GREEN "
==========================================
✅ Generation completed successfully!
==========================================
"
    
    if [ -f "$OUTPUT_FILE" ]; then
        SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
        print_msg $GREEN "LUT file created: $OUTPUT_FILE ($SIZE)"
    fi
else
    print_msg $RED "
==========================================
❌ Generation failed with code $exit_code
==========================================
"
    
    if [ $exit_code -eq 137 ]; then
        print_msg $YELLOW "
Memory limit exceeded (OOM kill). Try:
1. Run recovery: $0 recover
2. Use emergency mode: $0 emergency
3. Check memory with: free -h
"
    else
        print_msg $YELLOW "
Troubleshooting:
1. Check memory usage with: free -h
2. Try recovery mode: $0 recover
3. Try emergency mode: $0 emergency
4. Check Python errors above
"
    fi
fi

exit $exit_code