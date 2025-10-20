#!/usr/bin/env bash
# Pre-commit hook to ensure BATS tests exist for recipe files
# This hook verifies that each numbered recipe markdown file has a corresponding BATS test

set -euo pipefail

RECIPE_PATTERN='^([0-9]{2}[a-z]?)-.*\.md$'
BATS_TESTS_DIR="test-framework/bats-tests/recipes"
EXIT_CODE=0

echo "Checking for BATS tests for modified recipe files..."

for file in "$@"; do
    # Only check recipe files (e.g., 01-deny-all.md, 02a-allow-all.md)
    if [[ $(basename "$file") =~ $RECIPE_PATTERN ]]; then
        recipe_num="${BASH_REMATCH[1]}"

        # Look for corresponding BATS test file
        # Pattern: test-framework/bats-tests/recipes/XX-*.bats or XX*-*.bats
        if ! find "$BATS_TESTS_DIR" -name "${recipe_num}*.bats" 2>/dev/null | grep -q .; then
            echo "ERROR: No BATS test found for recipe: $file"
            echo "  Expected: ${BATS_TESTS_DIR}/${recipe_num}-*.bats"
            echo "  Please create a BATS test file for this recipe before committing."
            EXIT_CODE=1
        else
            echo "  ✓ BATS test found for $file"
        fi
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo "All recipe files have corresponding BATS tests."
fi

exit $EXIT_CODE
