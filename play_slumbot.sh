#!/bin/bash
# Play against Slumbot with your trained poker AI

# Default values
HANDS=100
USERNAME="hello_007_poker_ai"
PASSWORD="hello_007_poker_ai"
STRATEGY_PATH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hands)
            HANDS="$2"
            shift 2
            ;;
        --strategy)
            STRATEGY_PATH="$2"
            shift 2
            ;;
        --no-auth)
            USERNAME=""
            PASSWORD=""
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --hands N        Number of hands to play (default: 100)"
            echo "  --strategy PATH  Path to strategy file (default: auto-detect)"
            echo "  --no-auth       Play without authentication"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Build command
CMD="python test_slumbot.py --hands $HANDS"

if [ -n "$STRATEGY_PATH" ]; then
    CMD="$CMD --strategy_path $STRATEGY_PATH"
fi

if [ -z "$USERNAME" ]; then
    CMD="$CMD --no-auth"
else
    CMD="$CMD --username $USERNAME --password $PASSWORD"
fi

echo "Starting Slumbot test session..."
echo "Command: $CMD"
echo "=================================="

# Run the test
$CMD