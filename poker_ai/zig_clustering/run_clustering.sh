#!/bin/bash

# Zig Clustering Runner Script
# Memory-efficient LUT generation using Zig

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Check if Zig is installed
if ! command -v zig &> /dev/null; then
    print_msg $RED "❌ Zig is not installed!"
    print_msg $YELLOW "Install with: brew install zig (macOS) or see https://ziglang.org/download/"
    exit 1
fi

# Parse command line arguments
MODE=${1:-normal}

print_msg $BLUE "
==========================================
  Zig Poker Clustering
  Mode: $MODE
==========================================
"

# Check Zig version
ZIG_VERSION=$(zig version)
print_msg $BLUE "Zig version: $ZIG_VERSION"

# Build the project
print_msg $GREEN "Building Zig clustering..."

if [ "$MODE" == "debug" ]; then
    zig build
else
    zig build -Doptimize=ReleaseFast
fi

if [ $? -ne 0 ]; then
    print_msg $RED "❌ Build failed!"
    exit 1
fi

print_msg $GREEN "✅ Build successful!"

# Check available memory
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    AVAILABLE_MEM=$(vm_stat | grep "Pages free" | awk '{print int($3*4096/1024/1024/1024)}')
else
    # Linux
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
fi

print_msg $BLUE "Available memory: ${AVAILABLE_MEM}GB"

# Run the clustering
print_msg $GREEN "Starting clustering process..."

case $MODE in
    emergency)
        print_msg $RED "🚨 Running in EMERGENCY MODE"
        ./zig-out/bin/poker_clustering emergency
        ;;
    
    test)
        print_msg $YELLOW "🧪 Running tests..."
        zig build test
        ;;
    
    benchmark)
        print_msg $YELLOW "📊 Running benchmark..."
        time ./zig-out/bin/poker_clustering
        ;;
    
    clean)
        print_msg $YELLOW "🧹 Cleaning build artifacts..."
        rm -rf zig-out zig-cache
        rm -f clustering_data.db
        print_msg $GREEN "✅ Cleaned!"
        exit 0
        ;;
    
    *)
        ./zig-out/bin/poker_clustering
        ;;
esac

exit_code=$?

if [ $exit_code -eq 0 ]; then
    print_msg $GREEN "
==========================================
✅ Clustering completed successfully!
==========================================
"
    
    if [ -f "clustering_data.db" ]; then
        SIZE=$(du -h "clustering_data.db" | cut -f1)
        print_msg $GREEN "Database size: $SIZE"
    fi
else
    print_msg $RED "
==========================================
❌ Clustering failed with code $exit_code
==========================================
"
fi

exit $exit_code