#!/usr/bin/env bash
# Enforce coverage thresholds and detect regressions in CI
# Part of the comprehensive test coverage reporting system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Enforce minimum coverage threshold
enforce_coverage_threshold() {
    local coverage="$1"
    local threshold="${2:-95}"

    echo "Checking coverage threshold..."
    echo "  Current coverage: ${coverage}%"
    echo "  Required threshold: ${threshold}%"

    if (( $(echo "$coverage < $threshold" | bc -l) )); then
        echo -e "${RED}❌ ERROR: Coverage ${coverage}% is below threshold ${threshold}%${NC}"
        echo ""
        echo "Coverage must be at least ${threshold}% to pass CI."
        echo "Please add more tests to increase coverage."
        return 1
    fi

    echo -e "${GREEN}✅ Coverage ${coverage}% meets threshold ${threshold}%${NC}"
    return 0
}

# Check for coverage regression compared to baseline
check_coverage_regression() {
    local current_coverage="$1"
    local baseline_file="${2:-test-framework/results/coverage-baseline.json}"
    local max_regression="${3:-1.0}"

    if [[ ! -f "$baseline_file" ]]; then
        echo -e "${YELLOW}⚠ No baseline found, creating new baseline${NC}"
        echo "$current_coverage" > "$baseline_file"
        return 0
    fi

    local baseline_coverage=$(cat "$baseline_file")
    local diff=$(echo "$current_coverage - $baseline_coverage" | bc)

    echo "Checking for coverage regression..."
    echo "  Baseline coverage: ${baseline_coverage}%"
    echo "  Current coverage:  ${current_coverage}%"
    echo "  Difference:        ${diff}%"

    if (( $(echo "$diff < -$max_regression" | bc -l) )); then
        echo -e "${RED}❌ ERROR: Coverage regression detected: ${diff}%${NC}"
        echo ""
        echo "Coverage has decreased by more than ${max_regression}% from baseline."
        echo "This indicates test coverage has gotten worse."
        echo ""
        echo "To fix this:"
        echo "  1. Add tests for uncovered code"
        echo "  2. Review recent changes that may have removed tests"
        echo "  3. If the regression is intentional, update the baseline"
        return 1
    elif (( $(echo "$diff < 0" | bc -l) )); then
        echo -e "${YELLOW}⚠ Warning: Minor coverage decrease of ${diff}%${NC}"
        return 0
    else
        echo -e "${GREEN}✅ No coverage regression (change: ${diff}%)${NC}"

        # Update baseline if coverage improved
        if (( $(echo "$diff > 0" | bc -l) )); then
            echo "  Coverage improved! Updating baseline."
            echo "$current_coverage" > "$baseline_file"
        fi
        return 0
    fi
}

# Enforce per-component coverage thresholds
enforce_component_thresholds() {
    local coverage_report="${1:-test-framework/results/coverage-report.json}"
    local bats_threshold="${2:-95}"
    local integration_threshold="${3:-90}"

    if [[ ! -f "$coverage_report" ]]; then
        echo -e "${RED}❌ ERROR: Coverage report not found at $coverage_report${NC}"
        return 1
    fi

    local bats_coverage=$(jq -r '.coverage.bats_unit_tests' "$coverage_report")
    local integration_coverage=$(jq -r '.coverage.integration_tests' "$coverage_report")
    local overall_status=0

    echo "Checking component-specific thresholds..."
    echo ""

    # Check BATS coverage
    echo "BATS Unit Tests:"
    echo "  Coverage: ${bats_coverage}%"
    echo "  Threshold: ${bats_threshold}%"
    if (( $(echo "$bats_coverage < $bats_threshold" | bc -l) )); then
        echo -e "  ${RED}❌ FAIL${NC}"
        overall_status=1
    else
        echo -e "  ${GREEN}✅ PASS${NC}"
    fi
    echo ""

    # Check integration coverage
    echo "Integration Tests:"
    echo "  Coverage: ${integration_coverage}%"
    echo "  Threshold: ${integration_threshold}%"
    if (( $(echo "$integration_coverage < $integration_threshold" | bc -l) )); then
        echo -e "  ${RED}❌ FAIL${NC}"
        overall_status=1
    else
        echo -e "  ${GREEN}✅ PASS${NC}"
    fi
    echo ""

    if [[ $overall_status -eq 0 ]]; then
        echo -e "${GREEN}✅ All component thresholds met${NC}"
    else
        echo -e "${RED}❌ One or more component thresholds not met${NC}"
    fi

    return $overall_status
}

# Check recipe coverage completeness
check_recipe_completeness() {
    local coverage_report="${1:-test-framework/results/coverage-report.json}"

    if [[ ! -f "$coverage_report" ]]; then
        echo -e "${RED}❌ ERROR: Coverage report not found at $coverage_report${NC}"
        return 1
    fi

    local recipe_coverage=$(jq -r '.coverage.recipe_coverage' "$coverage_report")
    local total_recipes=$(jq -r '.details.total_recipes' "$coverage_report")

    echo "Recipe Coverage Completeness:"
    echo "  Coverage: ${recipe_coverage}%"
    echo "  Total recipes: ${total_recipes}"

    if (( $(echo "$recipe_coverage < 100" | bc -l) )); then
        echo -e "  ${YELLOW}⚠ Warning: Not all recipes have tests${NC}"

        # List recipes without tests (if available)
        echo ""
        echo "Recipes missing tests:"
        for i in $(seq -w 0 14); do
            if ! compgen -G "test-framework/bats-tests/recipes/${i}-"*.bats > /dev/null 2>&1 && \
               ! compgen -G "test-framework/bats-tests/recipes/${i}a-"*.bats > /dev/null 2>&1; then
                echo "  - Recipe ${i}"
            fi
        done
        return 1
    else
        echo -e "  ${GREEN}✅ All recipes have tests${NC}"
        return 0
    fi
}

# Generate coverage diff for pull requests
generate_coverage_diff() {
    local current_report="${1:-test-framework/results/coverage-report.json}"
    local baseline_report="${2:-test-framework/results/coverage-baseline-report.json}"
    local output_file="${3:-test-framework/results/coverage-diff.json}"

    if [[ ! -f "$current_report" ]]; then
        echo -e "${RED}❌ ERROR: Current coverage report not found${NC}"
        return 1
    fi

    if [[ ! -f "$baseline_report" ]]; then
        echo -e "${YELLOW}⚠ No baseline report found, cannot generate diff${NC}"
        return 0
    fi

    local current_overall=$(jq -r '.coverage.overall' "$current_report")
    local baseline_overall=$(jq -r '.coverage.overall' "$baseline_report")
    local diff=$(echo "$current_overall - $baseline_overall" | bc)

    local current_bats=$(jq -r '.coverage.bats_unit_tests' "$current_report")
    local baseline_bats=$(jq -r '.coverage.bats_unit_tests' "$baseline_report")
    local bats_diff=$(echo "$current_bats - $baseline_bats" | bc)

    local current_integration=$(jq -r '.coverage.integration_tests' "$current_report")
    local baseline_integration=$(jq -r '.coverage.integration_tests' "$baseline_report")
    local integration_diff=$(echo "$current_integration - $baseline_integration" | bc)

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
  "current": {
    "overall": ${current_overall},
    "bats": ${current_bats},
    "integration": ${current_integration}
  },
  "baseline": {
    "overall": ${baseline_overall},
    "bats": ${baseline_bats},
    "integration": ${baseline_integration}
  },
  "diff": {
    "overall": ${diff},
    "bats": ${bats_diff},
    "integration": ${integration_diff}
  }
}
EOF

    echo "Coverage diff generated: $output_file"
    cat "$output_file"
}

# Format coverage diff for PR comment
format_coverage_diff_for_pr() {
    local diff_file="${1:-test-framework/results/coverage-diff.json}"

    if [[ ! -f "$diff_file" ]]; then
        echo "No coverage diff available"
        return 0
    fi

    local overall_diff=$(jq -r '.diff.overall' "$diff_file")
    local bats_diff=$(jq -r '.diff.bats' "$diff_file")
    local integration_diff=$(jq -r '.diff.integration' "$diff_file")

    local current_overall=$(jq -r '.current.overall' "$diff_file")
    local current_bats=$(jq -r '.current.bats' "$diff_file")
    local current_integration=$(jq -r '.current.integration' "$diff_file")

    # Determine emoji based on diff
    local overall_emoji="➡️"
    if (( $(echo "$overall_diff > 0" | bc -l) )); then
        overall_emoji="📈"
    elif (( $(echo "$overall_diff < 0" | bc -l) )); then
        overall_emoji="📉"
    fi

    cat <<EOF
### 📊 Coverage Change

| Metric | Current | Change |
|--------|---------|--------|
| Overall | ${current_overall}% | ${overall_emoji} ${overall_diff:0:1}${overall_diff#-}% |
| BATS | ${current_bats}% | ${bats_diff:0:1}${bats_diff#-}% |
| Integration | ${current_integration}% | ${integration_diff:0:1}${integration_diff#-}% |
EOF
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-threshold}" in
        threshold)
            enforce_coverage_threshold "$2" "${3:-95}"
            ;;
        regression)
            check_coverage_regression "$2" "${3:-test-framework/results/coverage-baseline.json}" "${4:-1.0}"
            ;;
        components)
            enforce_component_thresholds "${2:-test-framework/results/coverage-report.json}" \
                "${3:-95}" "${4:-90}"
            ;;
        recipes)
            check_recipe_completeness "${2:-test-framework/results/coverage-report.json}"
            ;;
        diff)
            generate_coverage_diff "${2:-test-framework/results/coverage-report.json}" \
                "${3:-test-framework/results/coverage-baseline-report.json}" \
                "${4:-test-framework/results/coverage-diff.json}"
            ;;
        pr-comment)
            format_coverage_diff_for_pr "${2:-test-framework/results/coverage-diff.json}"
            ;;
        all)
            echo "Running all coverage checks..."
            echo ""

            report="${2:-test-framework/results/coverage-report.json}"
            overall=$(jq -r '.coverage.overall' "$report")

            enforce_coverage_threshold "$overall" 95 && \
            check_coverage_regression "$overall" && \
            enforce_component_thresholds "$report" && \
            check_recipe_completeness "$report"
            ;;
        *)
            echo "Usage: $0 {threshold|regression|components|recipes|diff|pr-comment|all} [args...]"
            echo ""
            echo "Commands:"
            echo "  threshold <coverage> [threshold]              - Enforce minimum coverage"
            echo "  regression <coverage> [baseline] [max_diff]   - Check for coverage regression"
            echo "  components [report] [bats_threshold] [int_threshold] - Check component thresholds"
            echo "  recipes [report]                              - Check recipe completeness"
            echo "  diff [current] [baseline] [output]            - Generate coverage diff"
            echo "  pr-comment [diff_file]                        - Format diff for PR comment"
            echo "  all [report]                                  - Run all checks"
            exit 1
            ;;
    esac
fi
