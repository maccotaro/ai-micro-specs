#!/bin/bash
# File size constraint check script
# Validates that all source files are under 500 lines

set -e

MAX_LINES=500
EXIT_CODE=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Checking file size constraints (max: ${MAX_LINES} lines)..."
echo ""

# Check Python files in ai-micro-api-admin
if [ -d "../../ai-micro-api-admin/app" ]; then
    echo "Checking Python files in ai-micro-api-admin..."
    while IFS= read -r -d '' file; do
        lines=$(wc -l < "$file")
        if [ "$lines" -gt "$MAX_LINES" ]; then
            echo -e "${RED}✗ FAIL${NC}: $file ($lines lines > $MAX_LINES)"
            EXIT_CODE=1
        else
            echo -e "${GREEN}✓ PASS${NC}: $file ($lines lines)"
        fi
    done < <(find ../../ai-micro-api-admin/app -type f -name "*.py" -print0)
fi

# Check TypeScript/JavaScript files in ai-micro-front-admin
if [ -d "../../ai-micro-front-admin/src" ]; then
    echo ""
    echo "Checking TypeScript/JavaScript files in ai-micro-front-admin..."
    while IFS= read -r -d '' file; do
        lines=$(wc -l < "$file")
        if [ "$lines" -gt "$MAX_LINES" ]; then
            echo -e "${RED}✗ FAIL${NC}: $file ($lines lines > $MAX_LINES)"
            EXIT_CODE=1
        else
            echo -e "${GREEN}✓ PASS${NC}: $file ($lines lines)"
        fi
    done < <(find ../../ai-micro-front-admin/src -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -print0)
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ All files pass the 500-line limit${NC}"
else
    echo -e "${RED}❌ Some files exceed the 500-line limit. Please refactor.${NC}"
fi

exit $EXIT_CODE
