#!/usr/bin/env bash
# kcov wrapper for bash script code coverage
# Provides easy interface to run scripts with coverage

set -euo pipefail

KCOV_OUTPUT_DIR="${KCOV_OUTPUT_DIR:-test-framework/results/kcov}"
KCOV_EXCLUDE_PATTERN="${KCOV_EXCLUDE_PATTERN:-/usr,/tmp,test-framework/bats-libs}"
KCOV_INCLUDE_PATTERN="${KCOV_INCLUDE_PATTERN:-test-framework}"

# Function to run a script with kcov coverage
run_with_coverage() {
    local script_path="$1"
    shift
    local script_args=("$@")

    if ! command -v kcov &> /dev/null; then
        echo "Error: kcov is not installed. Run test-framework/install-kcov.sh first."
        return 1
    fi

    # Get script name without path and extension
    local script_name
    script_name=$(basename "$script_path" | sed 's/\.[^.]*$//')

    # Create output directory
    local output_dir="${KCOV_OUTPUT_DIR}/${script_name}"
    mkdir -p "$output_dir"

    echo "Running $script_path with kcov coverage..."
    echo "Output directory: $output_dir"

    # Run kcov with the script
    kcov \
        --exclude-pattern="$KCOV_EXCLUDE_PATTERN" \
        --include-pattern="$KCOV_INCLUDE_PATTERN" \
        --bash-dont-parse-binary-dir \
        "$output_dir" \
        "$script_path" "${script_args[@]}"

    local exit_code=$?

    echo "Coverage report generated: $output_dir/index.html"
    return $exit_code
}

# Function to run BATS tests with coverage
run_bats_with_coverage() {
    local test_file="$1"

    if ! command -v kcov &> /dev/null; then
        echo "Error: kcov is not installed. Run test-framework/install-kcov.sh first."
        return 1
    fi

    local test_name
    test_name=$(basename "$test_file" .bats)

    local output_dir="${KCOV_OUTPUT_DIR}/bats-${test_name}"
    mkdir -p "$output_dir"

    echo "Running BATS test $test_file with kcov coverage..."

    # Find BATS executable
    local bats_bin="test-framework/bats-libs/bats-core/bin/bats"

    if [ ! -f "$bats_bin" ]; then
        bats_bin=$(command -v bats)
    fi

    # Run BATS with kcov
    kcov \
        --exclude-pattern="$KCOV_EXCLUDE_PATTERN" \
        --include-pattern="$KCOV_INCLUDE_PATTERN" \
        --bash-dont-parse-binary-dir \
        "$output_dir" \
        "$bats_bin" "$test_file"

    local exit_code=$?

    echo "Coverage report generated: $output_dir/index.html"
    return $exit_code
}

# Function to merge multiple kcov reports
merge_coverage_reports() {
    local merged_output="${KCOV_OUTPUT_DIR}/merged"

    if ! command -v kcov &> /dev/null; then
        echo "Error: kcov is not installed."
        return 1
    fi

    echo "Merging coverage reports..."
    mkdir -p "$merged_output"

    # Find all kcov output directories
    local coverage_dirs=()
    while IFS= read -r -d '' dir; do
        if [ -f "$dir/coverage.json" ]; then
            coverage_dirs+=("$dir")
        fi
    done < <(find "$KCOV_OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

    if [ ${#coverage_dirs[@]} -eq 0 ]; then
        echo "No coverage reports found to merge."
        return 1
    fi

    echo "Found ${#coverage_dirs[@]} coverage reports to merge"

    # Merge using kcov
    kcov --merge "$merged_output" "${coverage_dirs[@]}"

    echo "Merged coverage report: $merged_output/index.html"
    return 0
}

# Function to extract coverage percentage from kcov report
get_coverage_percentage() {
    local kcov_dir="$1"
    local coverage_json="${kcov_dir}/coverage.json"

    if [ ! -f "$coverage_json" ]; then
        echo "0.0"
        return 1
    fi

    # Extract line coverage percentage
    local coverage
    coverage=$(jq -r '.percent_covered // 0' "$coverage_json" 2>/dev/null || echo "0.0")

    echo "$coverage"
}

# Function to generate coverage badge
generate_coverage_badge() {
    local coverage_percentage="$1"
    local badge_file="${2:-badges/coverage.json}"

    mkdir -p "$(dirname "$badge_file")"

    # Determine badge color
    local color
    if (( $(echo "$coverage_percentage >= 90" | bc -l) )); then
        color="brightgreen"
    elif (( $(echo "$coverage_percentage >= 75" | bc -l) )); then
        color="green"
    elif (( $(echo "$coverage_percentage >= 60" | bc -l) )); then
        color="yellow"
    elif (( $(echo "$coverage_percentage >= 40" | bc -l) )); then
        color="orange"
    else
        color="red"
    fi

    # Generate shields.io compatible badge data
    cat > "$badge_file" <<EOF
{
  "schemaVersion": 1,
  "label": "code coverage",
  "message": "${coverage_percentage}%",
  "color": "$color"
}
EOF

    echo "Coverage badge generated: $badge_file"
}

# Main function when script is executed directly
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        run)
            if [ $# -lt 1 ]; then
                echo "Usage: $0 run <script> [args...]"
                return 1
            fi
            run_with_coverage "$@"
            ;;
        bats)
            if [ $# -lt 1 ]; then
                echo "Usage: $0 bats <test-file.bats>"
                return 1
            fi
            run_bats_with_coverage "$1"
            ;;
        merge)
            merge_coverage_reports
            ;;
        percentage)
            if [ $# -lt 1 ]; then
                echo "Usage: $0 percentage <kcov-output-dir>"
                return 1
            fi
            get_coverage_percentage "$1"
            ;;
        badge)
            if [ $# -lt 1 ]; then
                echo "Usage: $0 badge <coverage-percentage> [badge-file]"
                return 1
            fi
            generate_coverage_badge "$@"
            ;;
        help|*)
            cat <<EOF
kcov wrapper for bash script code coverage

Usage:
  $0 run <script> [args...]        Run a bash script with coverage
  $0 bats <test-file.bats>         Run a BATS test with coverage
  $0 merge                         Merge all coverage reports
  $0 percentage <kcov-dir>         Get coverage percentage from report
  $0 badge <percentage> [file]     Generate coverage badge
  $0 help                          Show this help

Environment variables:
  KCOV_OUTPUT_DIR                  Output directory for reports (default: test-framework/results/kcov)
  KCOV_EXCLUDE_PATTERN             Paths to exclude from coverage (default: /usr,/tmp,test-framework/bats-libs)
  KCOV_INCLUDE_PATTERN             Paths to include in coverage (default: test-framework)

Examples:
  $0 run test-framework/parallel-test-runner.sh
  $0 bats test-framework/bats-tests/recipes/01-deny-all-traffic.bats
  $0 merge
  $0 percentage test-framework/results/kcov/merged
EOF
            ;;
    esac
}

# Execute main if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
