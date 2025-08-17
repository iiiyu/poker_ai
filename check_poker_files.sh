#!/bin/bash
# Check for all poker AI related files in the current directory

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================="
echo "     POKER AI FILE STATUS CHECK"
echo "==========================================${NC}"
echo ""

# Function to format file size
format_size() {
    if [ -f "$1" ]; then
        ls -lh "$1" | awk '{print $5}'
    else
        echo "N/A"
    fi
}

# Function to get file age
get_age() {
    if [ -f "$1" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$1"
        else
            # Linux
            stat -c "%y" "$1" | cut -d' ' -f1,2 | cut -d'.' -f1
        fi
    else
        echo "N/A"
    fi
}

# Check for LUT files
echo -e "${GREEN}=== LUT Files ===${NC}"
echo ""

if [ -f "card_info_lut.joblib" ]; then
    echo -e "${GREEN}✅ Main LUT:${NC} card_info_lut.joblib"
    echo "   Size: $(format_size card_info_lut.joblib)"
    echo "   Modified: $(get_age card_info_lut.joblib)"
    
    # Check completeness
    STAGES=$(python3 -c "
import joblib
try:
    lut = joblib.load('card_info_lut.joblib')
    if isinstance(lut, dict):
        stages = list(lut.keys())
        print(f'Stages: {len(stages)} - {\" \".join(stages)}')
        complete = all(s in stages for s in ['pre_flop', 'river', 'turn', 'flop'])
        if complete:
            print('Status: COMPLETE ✅')
        else:
            print('Status: INCOMPLETE ⚠️')
    else:
        print('Status: Invalid format ❌')
except Exception as e:
    print(f'Status: Cannot read - {str(e)}')
" 2>/dev/null || echo "Status: Cannot verify")
    echo "   $STAGES"
else
    echo -e "${YELLOW}❌ No main LUT file (card_info_lut.joblib)${NC}"
fi

echo ""

# Check for descriptive LUT files
for file in texas_holdem_*_lut.joblib; do
    if [ -f "$file" ] && [ "$file" != "texas_holdem_*_lut.joblib" ]; then
        echo -e "${BLUE}📁 Backup LUT:${NC} $file"
        echo "   Size: $(format_size "$file")"
        echo "   Modified: $(get_age "$file")"
    fi
done

# Check for centroids
if [ -f "centroids.joblib" ]; then
    echo ""
    echo -e "${GREEN}✅ Centroids:${NC} centroids.joblib"
    echo "   Size: $(format_size centroids.joblib)"
    echo "   Modified: $(get_age centroids.joblib)"
fi

# Check for checkpoints
echo ""
echo -e "${YELLOW}=== Checkpoint Files ===${NC}"
echo ""

checkpoint_found=0
for checkpoint in checkpoint_*.joblib; do
    if [ -f "$checkpoint" ] && [ "$checkpoint" != "checkpoint_*.joblib" ]; then
        checkpoint_found=1
        stage=$(echo $checkpoint | sed 's/checkpoint_\(.*\)\.joblib/\1/')
        echo -e "${BLUE}💾 Checkpoint:${NC} $checkpoint"
        echo "   Stage: $stage"
        echo "   Size: $(format_size "$checkpoint")"
        echo "   Modified: $(get_age "$checkpoint")"
    fi
done

if [ $checkpoint_found -eq 0 ]; then
    echo -e "${YELLOW}No checkpoint files found${NC}"
fi

# Check for strategy files
echo ""
echo -e "${CYAN}=== Strategy Files ===${NC}"
echo ""

strategy_found=0
for strategy in offline_strategy_*.pkl.gz offline_strategy_*.pkl; do
    if [ -f "$strategy" ]; then
        strategy_found=1
        echo -e "${GREEN}🎯 Strategy:${NC} $strategy"
        echo "   Size: $(format_size "$strategy")"
        echo "   Modified: $(get_age "$strategy")"
    fi
done

if [ $strategy_found -eq 0 ]; then
    echo -e "${YELLOW}No strategy files found${NC}"
fi

# Check for backup files
echo ""
echo -e "${BLUE}=== Backup Files ===${NC}"
echo ""

backup_found=0
for backup in *.bak *.backup; do
    if [ -f "$backup" ]; then
        backup_found=1
        echo -e "${BLUE}💾 Backup:${NC} $backup"
        echo "   Size: $(format_size "$backup")"
        echo "   Modified: $(get_age "$backup")"
    fi
done

if [ $backup_found -eq 0 ]; then
    echo -e "${YELLOW}No backup files found${NC}"
fi

# Summary and recommendations
echo ""
echo -e "${CYAN}=========================================="
echo "            RECOMMENDATIONS"
echo "==========================================${NC}"
echo ""

if [ -f "card_info_lut.joblib" ]; then
    echo -e "${GREEN}✅ Main LUT exists${NC}"
    echo "   You can start training with: ./train_ai.sh"
else
    if ls texas_holdem_*_lut.joblib 1> /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  You have backup LUTs but no main file${NC}"
        echo "   Restore with: cp texas_holdem_*_lut.joblib card_info_lut.joblib"
    else
        echo -e "${RED}❌ No LUT files found${NC}"
        echo "   Generate with: ./generate_texas_holdem_lut_safe.sh standard"
    fi
fi

if [ $checkpoint_found -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Checkpoint files detected${NC}"
    echo "   These may indicate incomplete generation"
    echo "   Try: ./generate_texas_holdem_lut_safe.sh standard resume"
fi

echo ""
echo -e "${CYAN}For detailed progress check, run:${NC}"
echo "   python check_lut_progress.py"
echo ""