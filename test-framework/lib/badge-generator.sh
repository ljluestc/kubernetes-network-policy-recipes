#!/usr/bin/env bash
# Generate shields.io compatible badges for test coverage and CI status
# Part of the comprehensive test coverage reporting system

set -euo pipefail

# Generate coverage badge in shields.io endpoint format
generate_coverage_badge() {
    local coverage="$1"
    local output_file="${2:-badges/coverage.json}"

    # Determine color based on coverage percentage
    local color="red"
    if (( $(echo "$coverage >= 95" | bc -l) )); then
        color="brightgreen"
    elif (( $(echo "$coverage >= 90" | bc -l) )); then
        color="green"
    elif (( $(echo "$coverage >= 75" | bc -l) )); then
        color="yellow"
    elif (( $(echo "$coverage >= 50" | bc -l) )); then
        color="orange"
    fi

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"

    # Generate shields.io endpoint JSON
    cat > "$output_file" <<EOF
{
  "schemaVersion": 1,
  "label": "coverage",
  "message": "${coverage}%",
  "color": "${color}"
}
EOF

    echo "Coverage badge generated: $output_file (${coverage}%, ${color})"
}

# Generate test count badge
generate_test_count_badge() {
    local test_count="$1"
    local output_file="${2:-badges/tests.json}"

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
  "schemaVersion": 1,
  "label": "tests",
  "message": "${test_count} passing",
  "color": "brightgreen"
}
EOF

    echo "Test count badge generated: $output_file (${test_count} tests)"
}

# Generate CI status badge
generate_ci_status_badge() {
    local status="$1"
    local output_file="${2:-badges/ci-status.json}"

    local color="red"
    local message="failing"

    if [[ "$status" == "passing" || "$status" == "PASS" ]]; then
        color="brightgreen"
        message="passing"
    elif [[ "$status" == "pending" ]]; then
        color="yellow"
        message="pending"
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
  "schemaVersion": 1,
  "label": "build",
  "message": "${message}",
  "color": "${color}"
}
EOF

    echo "CI status badge generated: $output_file (${message})"
}

# Generate BATS coverage badge
generate_bats_badge() {
    local coverage="$1"
    local output_file="${2:-badges/bats-coverage.json}"

    local color="red"
    if (( $(echo "$coverage >= 95" | bc -l) )); then
        color="brightgreen"
    elif (( $(echo "$coverage >= 90" | bc -l) )); then
        color="green"
    elif (( $(echo "$coverage >= 75" | bc -l) )); then
        color="yellow"
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
  "schemaVersion": 1,
  "label": "BATS coverage",
  "message": "${coverage}%",
  "color": "${color}"
}
EOF

    echo "BATS coverage badge generated: $output_file (${coverage}%)"
}

# Generate integration test coverage badge
generate_integration_badge() {
    local coverage="$1"
    local output_file="${2:-badges/integration-coverage.json}"

    local color="red"
    if (( $(echo "$coverage >= 95" | bc -l) )); then
        color="brightgreen"
    elif (( $(echo "$coverage >= 90" | bc -l) )); then
        color="green"
    elif (( $(echo "$coverage >= 75" | bc -l) )); then
        color="yellow"
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
  "schemaVersion": 1,
  "label": "integration coverage",
  "message": "${coverage}%",
  "color": "${color}"
}
EOF

    echo "Integration coverage badge generated: $output_file (${coverage}%)"
}

# Generate recipe coverage badge
generate_recipe_badge() {
    local coverage="$1"
    local output_file="${2:-badges/recipe-coverage.json}"

    local color="red"
    if (( $(echo "$coverage >= 95" | bc -l) )); then
        color="brightgreen"
    elif (( $(echo "$coverage >= 90" | bc -l) )); then
        color="green"
    elif (( $(echo "$coverage >= 75" | bc -l) )); then
        color="yellow"
    fi

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
  "schemaVersion": 1,
  "label": "recipe coverage",
  "message": "${coverage}%",
  "color": "${color}"
}
EOF

    echo "Recipe coverage badge generated: $output_file (${coverage}%)"
}

# Generate all badges from coverage report
generate_all_badges() {
    local coverage_report="${1:-test-framework/results/coverage-report.json}"
    local badges_dir="${2:-badges}"

    if [[ ! -f "$coverage_report" ]]; then
        echo "Error: Coverage report not found at $coverage_report"
        return 1
    fi

    # Extract metrics from coverage report
    local overall=$(jq -r '.coverage.overall' "$coverage_report")
    local bats=$(jq -r '.coverage.bats_unit_tests' "$coverage_report")
    local integration=$(jq -r '.coverage.integration_tests' "$coverage_report")
    local recipe=$(jq -r '.coverage.recipe_coverage' "$coverage_report")
    local test_count=$(jq -r '.details.total_test_cases' "$coverage_report")
    local status=$(jq -r '.thresholds.status' "$coverage_report")

    # Generate all badges
    echo "Generating all badges from coverage report..."
    generate_coverage_badge "$overall" "${badges_dir}/coverage.json"
    generate_bats_badge "$bats" "${badges_dir}/bats-coverage.json"
    generate_integration_badge "$integration" "${badges_dir}/integration-coverage.json"
    generate_recipe_badge "$recipe" "${badges_dir}/recipe-coverage.json"
    generate_test_count_badge "$test_count" "${badges_dir}/tests.json"
    generate_ci_status_badge "$status" "${badges_dir}/ci-status.json"

    echo ""
    echo "✅ All badges generated successfully in ${badges_dir}/"
}

# Generate markdown badges for README
generate_readme_badges() {
    local repo_url="${1:-https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/badges}"
    local output_file="${2:-badges/README-badges.md}"

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
<!-- Test Coverage Badges -->
![Overall Coverage](https://img.shields.io/endpoint?url=${repo_url}/coverage.json)
![BATS Coverage](https://img.shields.io/endpoint?url=${repo_url}/bats-coverage.json)
![Integration Coverage](https://img.shields.io/endpoint?url=${repo_url}/integration-coverage.json)
![Recipe Coverage](https://img.shields.io/endpoint?url=${repo_url}/recipe-coverage.json)
![Test Count](https://img.shields.io/endpoint?url=${repo_url}/tests.json)
![CI Status](https://img.shields.io/endpoint?url=${repo_url}/ci-status.json)
EOF

    echo "README badges markdown generated: $output_file"
    cat "$output_file"
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-all}" in
        all)
            generate_all_badges "${2:-test-framework/results/coverage-report.json}" "${3:-badges}"
            ;;
        coverage)
            generate_coverage_badge "$2" "${3:-badges/coverage.json}"
            ;;
        bats)
            generate_bats_badge "$2" "${3:-badges/bats-coverage.json}"
            ;;
        integration)
            generate_integration_badge "$2" "${3:-badges/integration-coverage.json}"
            ;;
        recipe)
            generate_recipe_badge "$2" "${3:-badges/recipe-coverage.json}"
            ;;
        tests)
            generate_test_count_badge "$2" "${3:-badges/tests.json}"
            ;;
        ci)
            generate_ci_status_badge "$2" "${3:-badges/ci-status.json}"
            ;;
        readme)
            generate_readme_badges "$2" "${3:-badges/README-badges.md}"
            ;;
        *)
            echo "Usage: $0 {all|coverage|bats|integration|recipe|tests|ci|readme} [args...]"
            echo ""
            echo "Commands:"
            echo "  all [coverage_report] [output_dir]  - Generate all badges from coverage report"
            echo "  coverage <percentage> [output_file] - Generate overall coverage badge"
            echo "  bats <percentage> [output_file]     - Generate BATS coverage badge"
            echo "  integration <percentage> [output]   - Generate integration coverage badge"
            echo "  recipe <percentage> [output_file]   - Generate recipe coverage badge"
            echo "  tests <count> [output_file]         - Generate test count badge"
            echo "  ci <status> [output_file]           - Generate CI status badge"
            echo "  readme [repo_url] [output_file]     - Generate README badge markdown"
            exit 1
            ;;
    esac
fi
