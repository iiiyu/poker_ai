#!/bin/bash
# Diagnostic script to see exactly what files exist

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================="
echo "        LUT FILES DIAGNOSTIC"
echo "==========================================${NC}"
echo ""

echo -e "${YELLOW}Current directory:${NC}"
pwd
echo ""

echo -e "${YELLOW}Looking for ANY .joblib files:${NC}"
echo "----------------------------------------"
ls -la *.joblib 2>/dev/null || echo "No .joblib files found"
echo ""

echo -e "${YELLOW}Looking for files with 'lut' in name:${NC}"
echo "----------------------------------------"
ls -la *lut* 2>/dev/null || echo "No files with 'lut' in name"
echo ""

echo -e "${YELLOW}Looking for files with 'LUT' in name:${NC}"
echo "----------------------------------------"
ls -la *LUT* 2>/dev/null || echo "No files with 'LUT' in name"
echo ""

echo -e "${YELLOW}Looking for checkpoint files:${NC}"
echo "----------------------------------------"
ls -la checkpoint* 2>/dev/null || echo "No checkpoint files found"
echo ""

echo -e "${YELLOW}Looking for centroids:${NC}"
echo "----------------------------------------"
ls -la centroids* 2>/dev/null || echo "No centroids files found"
echo ""

echo -e "${YELLOW}Looking for any pkl files (strategies):${NC}"
echo "----------------------------------------"
ls -la *.pkl* 2>/dev/null || echo "No .pkl files found"
echo ""

echo -e "${YELLOW}Total .joblib files in directory:${NC}"
echo "----------------------------------------"
find . -maxdepth 1 -name "*.joblib" -type f 2>/dev/null | wc -l
echo ""

echo -e "${YELLOW}All files over 50MB (likely LUTs):${NC}"
echo "----------------------------------------"
find . -maxdepth 1 -type f -size +50M -exec ls -lh {} \; 2>/dev/null || echo "No large files found"
echo ""

echo -e "${CYAN}=========================================="
echo "         PYTHON CHECK"
echo "==========================================${NC}"
echo ""

python3 -c "
import os
import glob

print('Python glob results:')
print('-' * 40)

# Check for various patterns
patterns = [
    'card_info_lut.joblib',
    'texas_holdem_*_lut.joblib',
    'checkpoint_*.joblib',
    '*.joblib',
    '*lut*',
    '*LUT*'
]

for pattern in patterns:
    files = glob.glob(pattern)
    if files:
        print(f'{pattern}: {files}')
    else:
        print(f'{pattern}: No matches')

print()
print('Files in current directory:')
print('-' * 40)
all_files = [f for f in os.listdir('.') if os.path.isfile(f)]
joblib_files = [f for f in all_files if f.endswith('.joblib')]
if joblib_files:
    print(f'Found {len(joblib_files)} .joblib files:')
    for f in joblib_files:
        size = os.path.getsize(f) / (1024*1024)  # MB
        print(f'  - {f} ({size:.1f} MB)')
else:
    print('No .joblib files found')
"

echo ""
echo -e "${CYAN}=========================================="
echo "         RECOMMENDATIONS"
echo "==========================================${NC}"
echo ""

# Check if card_info_lut.joblib exists
if [ -f "card_info_lut.joblib" ]; then
    echo -e "${GREEN}✅ Main LUT file exists${NC}"
    echo "   Try: ./generate_texas_holdem_lut_safe.sh standard status"
elif ls *.joblib 2>/dev/null | grep -q "lut"; then
    echo -e "${YELLOW}⚠️ Found LUT-like files but not main card_info_lut.joblib${NC}"
    echo "   Files found:"
    ls -la *lut*.joblib 2>/dev/null
    echo ""
    echo "   Options:"
    echo "   1. Rename to main file: mv [your_file].joblib card_info_lut.joblib"
    echo "   2. Start fresh: ./generate_texas_holdem_lut_safe.sh test"
else
    echo -e "${BLUE}ℹ️ No LUT files detected${NC}"
    echo "   This is normal if you haven't generated one yet."
    echo "   Start with: ./generate_texas_holdem_lut_safe.sh test"
    echo ""
    echo "   Expected generation times:"
    echo "   - test mode: 30-60 minutes"
    echo "   - standard mode: 2-4 hours"
    echo "   - high mode: 6-10 hours"
fi

echo ""
echo -e "${CYAN}Debug info for safe script:${NC}"
echo "----------------------------------------"
echo "The safe script looks for these exact patterns:"
echo "  1. card_info_lut.joblib"
echo "  2. texas_holdem_*_lut.joblib"
echo "  3. checkpoint_*.joblib"
echo ""
echo "Your files must match these patterns exactly."
echo ""