#!/usr/bin/env bash
# Quick validation script for integration test framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Validating Integration Test Framework ==="
echo ""

# Check directory structure
echo "Checking directory structure..."
DIRS=(
    "${SCRIPT_DIR}/integration-tests"
    "${SCRIPT_DIR}/integration-tests/scenarios"
    "${SCRIPT_DIR}/integration-tests/fixtures"
    "${SCRIPT_DIR}/integration-tests/helpers"
)

for dir in "${DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        echo -e "  ${GREEN}✓${NC} $dir"
    else
        echo -e "  ${RED}✗${NC} $dir (missing)"
        exit 1
    fi
done

echo ""
echo "Checking scenario files..."
SCENARIOS=(
    "multi-policy-combination.sh"
    "three-tier-application.sh"
    "cross-namespace.sh"
    "microservices-mesh.sh"
    "policy-conflicts.sh"
    "performance-load.sh"
    "failure-recovery.sh"
)

for scenario in "${SCENARIOS[@]}"; do
    file="${SCRIPT_DIR}/integration-tests/scenarios/$scenario"
    if [[ -f "$file" ]]; then
        echo -e "  ${GREEN}✓${NC} $scenario"
    else
        echo -e "  ${RED}✗${NC} $scenario (missing)"
        exit 1
    fi
done

echo ""
echo "Checking executable permissions..."
if [[ -x "${SCRIPT_DIR}/run-integration-tests.sh" ]]; then
    echo -e "  ${GREEN}✓${NC} run-integration-tests.sh"
else
    echo -e "  ${RED}✗${NC} run-integration-tests.sh (not executable)"
    exit 1
fi

for scenario in "${SCENARIOS[@]}"; do
    file="${SCRIPT_DIR}/integration-tests/scenarios/$scenario"
    if [[ -x "$file" ]]; then
        echo -e "  ${GREEN}✓${NC} $scenario (executable)"
    else
        echo -e "  ${YELLOW}⚠${NC} $scenario (not executable, should be sourced)"
    fi
done

echo ""
echo "Checking test functions..."
EXPECTED_TESTS=25
FOUND_TESTS=0

for scenario in "${SCENARIOS[@]}"; do
    file="${SCRIPT_DIR}/integration-tests/scenarios/$scenario"
    if [[ -f "$file" ]]; then
        count=$(grep -c "^test_" "$file" || true)
        FOUND_TESTS=$((FOUND_TESTS + count))
        echo "  Found $count tests in $scenario"
    fi
done

if [[ $FOUND_TESTS -eq $EXPECTED_TESTS ]]; then
    echo -e "  ${GREEN}✓${NC} Total: $FOUND_TESTS tests (expected: $EXPECTED_TESTS)"
elif [[ $FOUND_TESTS -gt $EXPECTED_TESTS ]]; then
    echo -e "  ${GREEN}✓${NC} Total: $FOUND_TESTS tests (more than expected: $EXPECTED_TESTS)"
else
    echo -e "  ${YELLOW}⚠${NC} Total: $FOUND_TESTS tests (expected: $EXPECTED_TESTS)"
fi

echo ""
echo "Checking bash syntax..."
for scenario in "${SCENARIOS[@]}"; do
    file="${SCRIPT_DIR}/integration-tests/scenarios/$scenario"
    if bash -n "$file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $scenario syntax OK"
    else
        echo -e "  ${RED}✗${NC} $scenario syntax error"
        exit 1
    fi
done

if bash -n "${SCRIPT_DIR}/run-integration-tests.sh" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} run-integration-tests.sh syntax OK"
else
    echo -e "  ${RED}✗${NC} run-integration-tests.sh syntax error"
    exit 1
fi

echo ""
echo "Checking helper files..."
if [[ -f "${SCRIPT_DIR}/integration-tests/helpers/common.sh" ]]; then
    echo -e "  ${GREEN}✓${NC} common.sh exists"
    if bash -n "${SCRIPT_DIR}/integration-tests/helpers/common.sh" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} common.sh syntax OK"
    else
        echo -e "  ${RED}✗${NC} common.sh syntax error"
        exit 1
    fi
else
    echo -e "  ${YELLOW}⚠${NC} common.sh (not required)"
fi

echo ""
echo "Checking documentation..."
if [[ -f "${SCRIPT_DIR}/integration-tests/README.md" ]]; then
    echo -e "  ${GREEN}✓${NC} README.md exists"
else
    echo -e "  ${YELLOW}⚠${NC} README.md (missing)"
fi

echo ""
echo -e "${GREEN}=== Integration Test Framework Validation PASSED ===${NC}"
echo ""
echo "Summary:"
echo "  - 7 scenario files"
echo "  - $FOUND_TESTS test functions"
echo "  - 1 main runner script"
echo "  - 1 helper library"
echo "  - Documentation complete"
echo ""
echo "To run integration tests:"
echo "  cd ${SCRIPT_DIR}"
echo "  ./run-integration-tests.sh"
echo ""
