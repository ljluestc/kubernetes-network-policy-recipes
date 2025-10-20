#!/bin/bash
# Validation Suite for Network Policy Recipe Files
# Checks completeness and consistency of all recipe markdown files

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
FILES_CHECKED=0
ISSUES_FOUND=0
WARNINGS=0

log() { echo -e "${BLUE}[CHECK]${NC} $*"; }
pass() { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; ((ISSUES_FOUND++)); }
warn() { echo -e "${YELLOW}⚠${NC} $*"; ((WARNINGS++)); }

# Required sections in each recipe
REQUIRED_SECTIONS=(
    "## Overview"
    "## Objectives"
    "## Background"
    "## Requirements"
    "## Acceptance Criteria"
)

# Check if file has required sections
check_sections() {
    local file=$1
    local missing=0

    for section in "${REQUIRED_SECTIONS[@]}"; do
        if ! grep -q "^$section" "$file"; then
            fail "$file: Missing section '$section'"
            ((missing++))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        pass "$file: All required sections present"
    fi

    return $missing
}

# Check if file has YAML frontmatter
check_frontmatter() {
    local file=$1

    if ! head -1 "$file" | grep -q "^---$"; then
        fail "$file: Missing YAML frontmatter"
        return 1
    fi

    # Check for required frontmatter fields
    local required_fields=("id:" "title:" "type:" "category:" "priority:" "status:")

    for field in "${required_fields[@]}"; do
        if ! head -20 "$file" | grep -q "^$field"; then
            warn "$file: Missing frontmatter field '$field'"
        fi
    done

    pass "$file: Has YAML frontmatter"
    return 0
}

# Check if file has NetworkPolicy YAML
check_yaml_policy() {
    local file=$1

    if ! grep -q '```yaml' "$file"; then
        fail "$file: No YAML code blocks found"
        return 1
    fi

    if ! grep -q "kind: NetworkPolicy" "$file"; then
        fail "$file: No NetworkPolicy YAML found"
        return 1
    fi

    # Extract and validate YAML
    local temp_yaml=$(mktemp)
    sed -n '/^```yaml$/,/^```$/p' "$file" | sed '1d;$d' > "$temp_yaml"

    if kubectl apply --dry-run=client -f "$temp_yaml" &>/dev/null; then
        pass "$file: NetworkPolicy YAML is valid"
        rm -f "$temp_yaml"
        return 0
    else
        fail "$file: NetworkPolicy YAML is invalid"
        rm -f "$temp_yaml"
        return 1
    fi
}

# Check for test commands
check_test_commands() {
    local file=$1

    if grep -q "kubectl.*run\|kubectl.*exec\|kubectl.*apply" "$file"; then
        pass "$file: Contains test/demo commands"
        return 0
    else
        warn "$file: No test commands found"
        return 1
    fi
}

# Main validation
main() {
    log "===== Network Policy Recipe Validation ====="
    echo ""

    # Find all recipe markdown files (excluding documentation files)
    local recipe_files=($(ls -1 [0-9][0-9]*.md 2>/dev/null || echo ""))

    if [[ ${#recipe_files[@]} -eq 0 ]]; then
        fail "No recipe files found"
        exit 1
    fi

    log "Found ${#recipe_files[@]} recipe files"
    echo ""

    # Validate each file
    for file in "${recipe_files[@]}"; do
        log "Validating: $file"
        ((FILES_CHECKED++))

        check_frontmatter "$file"
        check_sections "$file"
        check_yaml_policy "$file"
        check_test_commands "$file"

        echo ""
    done

    # Summary
    log "===== Validation Summary ====="
    echo "Files checked: $FILES_CHECKED"
    echo -e "${RED}Issues found: $ISSUES_FOUND${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo ""

    if [[ $ISSUES_FOUND -eq 0 ]]; then
        pass "All recipes are valid!"
        exit 0
    else
        fail "Found $ISSUES_FOUND issues in recipes"
        exit 1
    fi
}

main
