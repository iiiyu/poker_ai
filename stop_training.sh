#!/bin/bash
# Stop all poker AI training processes

echo "Stopping all poker AI training processes..."

# Kill training scripts
pkill -f "train_ai.sh" 2>/dev/null
pkill -f "train_long_ai.py" 2>/dev/null
pkill -f "poker_ai train" 2>/dev/null

# Kill multiprocessing workers
pkill -f "multiprocessing.spawn" 2>/dev/null
pkill -f "multiprocessing.resource_tracker" 2>/dev/null

# Give processes time to clean up
sleep 2

# Check if any processes remain
remaining=$(ps aux | grep -E "(poker|train|multiprocessing)" | grep -v grep | wc -l)

if [ $remaining -gt 0 ]; then
    echo "Some processes still running. Force killing..."
    pkill -9 -f "train_ai.sh" 2>/dev/null
    pkill -9 -f "train_long_ai.py" 2>/dev/null
    pkill -9 -f "poker_ai train" 2>/dev/null
    pkill -9 -f "multiprocessing" 2>/dev/null
    sleep 1
fi

echo "All training processes stopped."

# Show any remaining python processes (for verification)
remaining=$(ps aux | grep -E "(poker|train)" | grep -v grep | wc -l)
if [ $remaining -gt 0 ]; then
    echo ""
    echo "Warning: Some processes may still be running:"
    ps aux | grep -E "(poker|train)" | grep -v grep
else
    echo "✓ No training processes running"
fi