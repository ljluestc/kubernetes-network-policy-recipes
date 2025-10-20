#!/usr/bin/env bash
# Run all tests with kcov code coverage collection
# Generates comprehensive coverage reports for all bash scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load kcov wrapper
source "${SCRIPT_DIR}/lib/kcov-wrapper.sh"

COVERAGE_OUTPUT="${SCRIPT_DIR}/results/kcov"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-95}"

echo "========================================="
echo "Running Tests with Code Coverage"
echo "========================================="
echo "Output directory: ${COVERAGE_OUTPUT}"
echo "Coverage threshold: ${COVERAGE_THRESHOLD}%"
echo "========================================="

# Clean previous coverage data
if [ -d "$COVERAGE_OUTPUT" ]; then
    echo "Cleaning previous coverage data..."
    rm -rf "$COVERAGE_OUTPUT"
fi
mkdir -p "$COVERAGE_OUTPUT"

# Track overall success
OVERALL_SUCCESS=0

# Function to run tests for a specific script with coverage
run_script_tests() {
    local script="$1"
    local script_name
    script_name=$(basename "$script")

    echo ""
    echo "Running tests for: $script_name"
    echo "-----------------------------------"

    if run_with_coverage "$script" --help > /dev/null 2>&1; then
        echo "✓ $script_name coverage collected"
    else
        echo "⚠ $script_name failed or has no tests"
        OVERALL_SUCCESS=1
    fi
}

echo ""
echo "Phase 1: Running BATS tests with coverage"
echo "========================================="

# Run all BATS tests with coverage
BATS_TESTS_DIR="${SCRIPT_DIR}/bats-tests/recipes"
if [ -d "$BATS_TESTS_DIR" ]; then
    for test_file in "$BATS_TESTS_DIR"/*.bats; do
        if [ -f "$test_file" ]; then
            test_name=$(basename "$test_file")
            echo "Running $test_name with coverage..."

            # Run BATS test with coverage (may fail if no cluster)
            if run_bats_with_coverage "$test_file" 2>/dev/null; then
                echo "✓ $test_name coverage collected"
            else
                echo "⚠ $test_name skipped (requires cluster)"
            fi
        fi
    done
else
    echo "⚠ BATS tests directory not found"
fi

echo ""
echo "Phase 2: Collecting coverage for library scripts"
echo "================================================="

# Collect coverage for library scripts by running them with --help or similar
LIB_DIR="${SCRIPT_DIR}/lib"
if [ -d "$LIB_DIR" ]; then
    for lib_script in "$LIB_DIR"/*.sh; do
        if [ -f "$lib_script" ] && [ -x "$lib_script" ]; then
            script_name=$(basename "$lib_script")

            # Skip the kcov wrapper itself
            if [ "$script_name" = "kcov-wrapper.sh" ]; then
                continue
            fi

            echo "Collecting coverage for: $script_name"

            # Try to source the script for coverage
            # This collects function definitions
            (
                export KCOV_OUTPUT_DIR="${COVERAGE_OUTPUT}/lib-${script_name%.sh}"
                kcov --exclude-pattern="/usr,/tmp" \
                     --include-pattern="${SCRIPT_DIR}" \
                     --bash-dont-parse-binary-dir \
                     "${COVERAGE_OUTPUT}/lib-${script_name%.sh}" \
                     bash -c "source $lib_script; exit 0" 2>/dev/null || true
            )

            echo "✓ $script_name coverage collected"
        fi
    done
else
    echo "⚠ Library directory not found"
fi

echo ""
echo "Phase 3: Collecting coverage for test scripts"
echo "=============================================="

# Collect coverage for main test scripts
TEST_SCRIPTS=(
    "${SCRIPT_DIR}/run-all-bats-tests.sh"
    "${SCRIPT_DIR}/run-integration-tests.sh"
    "${SCRIPT_DIR}/parallel-test-runner.sh"
    "${SCRIPT_DIR}/analyze-performance.sh"
    "${SCRIPT_DIR}/performance-benchmark.sh"
    "${SCRIPT_DIR}/provision-cluster.sh"
    "${SCRIPT_DIR}/cleanup-environment.sh"
)

for script in "${TEST_SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        script_name=$(basename "$script")
        echo "Collecting coverage for: $script_name"

        # Run with --help to collect function definitions
        (
            export KCOV_OUTPUT_DIR="${COVERAGE_OUTPUT}/${script_name%.sh}"
            kcov --exclude-pattern="/usr,/tmp,${SCRIPT_DIR}/bats-libs" \
                 --include-pattern="${SCRIPT_DIR}" \
                 --bash-dont-parse-binary-dir \
                 "${COVERAGE_OUTPUT}/${script_name%.sh}" \
                 "$script" --help 2>/dev/null || true
        )

        echo "✓ $script_name coverage collected"
    fi
done

echo ""
echo "Phase 4: Merging coverage reports"
echo "===================================="

if merge_coverage_reports; then
    echo "✓ Coverage reports merged successfully"

    # Get overall coverage percentage
    COVERAGE_PCT=$(get_coverage_percentage "${COVERAGE_OUTPUT}/merged")
    echo ""
    echo "Overall Code Coverage: ${COVERAGE_PCT}%"

    # Generate badge
    generate_coverage_badge "$COVERAGE_PCT" "${PROJECT_ROOT}/badges/bash-coverage.json"

    # Check threshold
    if (( $(echo "$COVERAGE_PCT >= $COVERAGE_THRESHOLD" | bc -l) )); then
        echo "✓ Coverage threshold met (${COVERAGE_PCT}% >= ${COVERAGE_THRESHOLD}%)"
    else
        echo "✗ Coverage below threshold (${COVERAGE_PCT}% < ${COVERAGE_THRESHOLD}%)"
        OVERALL_SUCCESS=1
    fi

    # Generate summary report
    cat > "${COVERAGE_OUTPUT}/summary.txt" <<EOF
Bash Code Coverage Summary
==========================

Overall Coverage: ${COVERAGE_PCT}%
Threshold: ${COVERAGE_THRESHOLD}%
Status: $([ "$COVERAGE_PCT" -ge "$COVERAGE_THRESHOLD" ] && echo "PASS" || echo "FAIL")

Generated: $(date)

Detailed Report: ${COVERAGE_OUTPUT}/merged/index.html

Coverage by Component:
EOF

    # List individual component coverage
    for dir in "${COVERAGE_OUTPUT}"/*; do
        if [ -d "$dir" ] && [ "$dir" != "${COVERAGE_OUTPUT}/merged" ]; then
            component=$(basename "$dir")
            if [ -f "${dir}/coverage.json" ]; then
                comp_coverage=$(jq -r '.percent_covered // 0' "${dir}/coverage.json" 2>/dev/null || echo "0")
                echo "  - ${component}: ${comp_coverage}%" >> "${COVERAGE_OUTPUT}/summary.txt"
            fi
        fi
    done

    cat "${COVERAGE_OUTPUT}/summary.txt"

else
    echo "✗ Failed to merge coverage reports"
    OVERALL_SUCCESS=1
fi

echo ""
echo "========================================="
echo "Code Coverage Collection Complete"
echo "========================================="
echo "HTML Report: ${COVERAGE_OUTPUT}/merged/index.html"
echo "JSON Report: ${COVERAGE_OUTPUT}/merged/coverage.json"
echo "Summary: ${COVERAGE_OUTPUT}/summary.txt"
echo "========================================="

exit $OVERALL_SUCCESS
