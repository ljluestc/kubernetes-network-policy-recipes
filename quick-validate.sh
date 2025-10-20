#!/bin/bash
# Quick Validation - No kubectl required

set -euo pipefail

echo "===== Quick Recipe Validation ====="
echo ""

# Find recipe files
RECIPE_FILES=($(ls -1 [0-9][0-9]*.md 2>/dev/null))

echo "Found ${#RECIPE_FILES[@]} recipe files"
echo ""

PASSED=0
WARNINGS=0

for file in "${RECIPE_FILES[@]}"; do
    echo -n "Checking $file ... "

    # Check frontmatter
    if ! head -1 "$file" | grep -q "^---$"; then
        echo "✗ NO FRONTMATTER"
        ((WARNINGS++))
        continue
    fi

    # Check for YAML
    if ! grep -q '```yaml' "$file"; then
        echo "✗ NO YAML"
        ((WARNINGS++))
        continue
    fi

    # Check for NetworkPolicy
    if ! grep -q "kind: NetworkPolicy" "$file"; then
        echo "✗ NO NetworkPolicy"
        ((WARNINGS++))
        continue
    fi

    echo "✓ PASS"
    ((PASSED++))
done

echo ""
echo "===== Summary ====="
echo "✓ Passed: $PASSED"
echo "✗ Issues: $WARNINGS"
echo ""

if [[ $WARNINGS -eq 0 ]]; then
    echo "✓ All recipes validated successfully!"
    exit 0
else
    echo "⚠ Some recipes have issues"
    exit 1
fi
