#!/usr/bin/env bash
# Coverage configuration and threshold management

# Default thresholds (can be overridden by .coveragerc)
COVERAGE_MINIMUM_OVERALL="${COVERAGE_MINIMUM_OVERALL:-95.0}"
COVERAGE_MINIMUM_BASH="${COVERAGE_MINIMUM_BASH:-95.0}"
COVERAGE_MINIMUM_UNIT="${COVERAGE_MINIMUM_UNIT:-100.0}"
COVERAGE_MINIMUM_INTEGRATION="${COVERAGE_MINIMUM_INTEGRATION:-100.0}"
COVERAGE_TARGET="${COVERAGE_TARGET:-100.0}"

# Load configuration from .coveragerc if it exists
load_coverage_config() {
    local config_file="${1:-.coveragerc}"

    if [ ! -f "$config_file" ]; then
        echo "Warning: Coverage config file not found: $config_file"
        return 1
    fi

    # Parse .coveragerc file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        case "$key" in
            minimum_overall)
                COVERAGE_MINIMUM_OVERALL="$value"
                ;;
            minimum_bash_scripts)
                COVERAGE_MINIMUM_BASH="$value"
                ;;
            minimum_unit_tests)
                COVERAGE_MINIMUM_UNIT="$value"
                ;;
            minimum_integration_tests)
                COVERAGE_MINIMUM_INTEGRATION="$value"
                ;;
            target)
                COVERAGE_TARGET="$value"
                ;;
            fail_under)
                COVERAGE_FAIL_UNDER="$value"
                ;;
        esac
    done < "$config_file"

    echo "Coverage configuration loaded from $config_file"
    return 0
}

# Check if coverage meets threshold
check_coverage_threshold() {
    local coverage="$1"
    local threshold="$2"
    local component_name="${3:-overall}"

    if (( $(echo "$coverage < $threshold" | bc -l) )); then
        echo "✗ $component_name coverage ($coverage%) is below threshold ($threshold%)"
        return 1
    else
        echo "✓ $component_name coverage ($coverage%) meets threshold ($threshold%)"
        return 0
    fi
}

# Validate all coverage thresholds
validate_coverage_thresholds() {
    local coverage_report="$1"

    if [ ! -f "$coverage_report" ]; then
        echo "Error: Coverage report not found: $coverage_report"
        return 1
    fi

    echo "Validating coverage thresholds..."
    echo "=================================="

    local all_passed=0

    # Check overall coverage
    local overall_coverage
    overall_coverage=$(jq -r '.coverage.overall // 0' "$coverage_report")
    if ! check_coverage_threshold "$overall_coverage" "$COVERAGE_MINIMUM_OVERALL" "Overall"; then
        all_passed=1
    fi

    # Check BATS unit test coverage
    local bats_coverage
    bats_coverage=$(jq -r '.coverage.bats_unit_tests // 0' "$coverage_report")
    if ! check_coverage_threshold "$bats_coverage" "$COVERAGE_MINIMUM_UNIT" "BATS Unit Tests"; then
        all_passed=1
    fi

    # Check integration test coverage
    local integration_coverage
    integration_coverage=$(jq -r '.coverage.integration_tests // 0' "$coverage_report")
    if ! check_coverage_threshold "$integration_coverage" "$COVERAGE_MINIMUM_INTEGRATION" "Integration Tests"; then
        all_passed=1
    fi

    # Check bash script coverage if available
    if jq -e '.coverage.bash_scripts' "$coverage_report" > /dev/null 2>&1; then
        local bash_coverage
        bash_coverage=$(jq -r '.coverage.bash_scripts // 0' "$coverage_report")
        if ! check_coverage_threshold "$bash_coverage" "$COVERAGE_MINIMUM_BASH" "Bash Scripts"; then
            all_passed=1
        fi
    fi

    echo "=================================="

    if [ $all_passed -eq 0 ]; then
        echo "✓ All coverage thresholds met!"
        return 0
    else
        echo "✗ Some coverage thresholds not met"
        return 1
    fi
}

# Check for coverage regression
check_coverage_regression() {
    local current_report="$1"
    local previous_report="${2:-test-framework/results/coverage-report-previous.json}"
    local max_regression="${3:-1.0}"

    if [ ! -f "$previous_report" ]; then
        echo "No previous coverage report found. Skipping regression check."
        return 0
    fi

    echo "Checking for coverage regression..."

    local current_coverage
    current_coverage=$(jq -r '.coverage.overall // 0' "$current_report")

    local previous_coverage
    previous_coverage=$(jq -r '.coverage.overall // 0' "$previous_report")

    local diff
    diff=$(echo "$current_coverage - $previous_coverage" | bc)

    echo "Current coverage: $current_coverage%"
    echo "Previous coverage: $previous_coverage%"
    echo "Difference: $diff%"

    if (( $(echo "$diff < -$max_regression" | bc -l) )); then
        echo "✗ Coverage regression detected! ($diff% < -$max_regression%)"
        return 1
    else
        echo "✓ No significant coverage regression"
        return 0
    fi
}

# Generate coverage quality gate report
generate_quality_gate_report() {
    local coverage_report="$1"
    local output_file="${2:-test-framework/results/quality-gate-report.txt}"

    echo "Generating quality gate report..."

    cat > "$output_file" <<EOF
========================================
Code Coverage Quality Gate Report
========================================
Generated: $(date)

Thresholds:
-----------
Overall Minimum:           ${COVERAGE_MINIMUM_OVERALL}%
Bash Scripts Minimum:      ${COVERAGE_MINIMUM_BASH}%
Unit Tests Minimum:        ${COVERAGE_MINIMUM_UNIT}%
Integration Tests Minimum: ${COVERAGE_MINIMUM_INTEGRATION}%
Target:                    ${COVERAGE_TARGET}%

Current Coverage:
-----------------
EOF

    # Extract coverage values
    local overall
    overall=$(jq -r '.coverage.overall // 0' "$coverage_report")
    local status
    status=$(jq -r '.thresholds.status // "UNKNOWN"' "$coverage_report")

    echo "Overall: ${overall}%" >> "$output_file"
    echo "Status: $status" >> "$output_file"
    echo "" >> "$output_file"

    # Component breakdown
    echo "Component Breakdown:" >> "$output_file"
    echo "-------------------" >> "$output_file"

    if jq -e '.coverage.bats_unit_tests' "$coverage_report" > /dev/null 2>&1; then
        local bats
        bats=$(jq -r '.coverage.bats_unit_tests // 0' "$coverage_report")
        echo "  BATS Unit Tests: ${bats}%" >> "$output_file"
    fi

    if jq -e '.coverage.integration_tests' "$coverage_report" > /dev/null 2>&1; then
        local integration
        integration=$(jq -r '.coverage.integration_tests // 0' "$coverage_report")
        echo "  Integration Tests: ${integration}%" >> "$output_file"
    fi

    if jq -e '.coverage.bash_scripts' "$coverage_report" > /dev/null 2>&1; then
        local bash
        bash=$(jq -r '.coverage.bash_scripts // 0' "$coverage_report")
        echo "  Bash Scripts: ${bash}%" >> "$output_file"
    fi

    echo "" >> "$output_file"
    echo "========================================" >> "$output_file"

    # Add pass/fail determination
    if validate_coverage_thresholds "$coverage_report" >> "$output_file" 2>&1; then
        echo "RESULT: ✓ PASS" >> "$output_file"
    else
        echo "RESULT: ✗ FAIL" >> "$output_file"
    fi

    echo "========================================" >> "$output_file"

    cat "$output_file"
    echo ""
    echo "Quality gate report saved to: $output_file"
}

# Export functions
export -f load_coverage_config
export -f check_coverage_threshold
export -f validate_coverage_thresholds
export -f check_coverage_regression
export -f generate_quality_gate_report
