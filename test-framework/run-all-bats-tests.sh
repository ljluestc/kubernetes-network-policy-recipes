#!/usr/bin/env bash
# Comprehensive BATS Test Runner for NetworkPolicy Recipes
# Executes all BATS tests with parallel execution, TAP/JUnit output, and detailed reporting

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_TESTS_DIR="${SCRIPT_DIR}/bats-tests/recipes"
RESULTS_DIR="${SCRIPT_DIR}/results/bats"
BATS_BIN="${SCRIPT_DIR}/bats-libs/bats-core/bin/bats"

# Default configuration
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-both}"  # tap, junit, both
VERBOSE="${VERBOSE:-false}"
FILTER_PATTERN="${FILTER_PATTERN:-}"
TIMEOUT="${TIMEOUT:-300}"  # 5 minutes per test file

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Run all BATS tests for NetworkPolicy recipes with comprehensive reporting.

OPTIONS:
    -j, --jobs NUM           Number of parallel jobs (default: 4)
    -f, --filter PATTERN     Only run tests matching pattern (e.g., "01,02,03")
    -o, --output FORMAT      Output format: tap, junit, both (default: both)
    -v, --verbose            Enable verbose output
    -t, --timeout SECONDS    Timeout per test file (default: 300)
    -c, --clean              Clean previous test results
    -h, --help               Show this help message

EXAMPLES:
    # Run all tests with default settings
    $0

    # Run tests 01-05 only with 8 parallel jobs
    $0 --filter "01,02,03,04,05" --jobs 8

    # Generate JUnit XML only
    $0 --output junit

    # Verbose mode with timeout of 600 seconds
    $0 --verbose --timeout 600

ENVIRONMENT VARIABLES:
    PARALLEL_JOBS    Number of parallel jobs
    OUTPUT_FORMAT    Output format (tap, junit, both)
    VERBOSE          Enable verbose output (true/false)
    FILTER_PATTERN   Pattern for test filtering
    TIMEOUT          Timeout per test file in seconds

EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -j|--jobs)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -c|--clean)
            rm -rf "${RESULTS_DIR}"
            echo "Cleaned previous test results"
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate BATS installation
if [[ ! -x "${BATS_BIN}" ]]; then
    echo -e "${RED}Error: BATS not found at ${BATS_BIN}${NC}"
    echo "Please ensure BATS is installed in test-framework/bats-libs/"
    exit 1
fi

# Create results directory
mkdir -p "${RESULTS_DIR}"/{tap,junit,logs}

# Print configuration
print_config() {
    echo -e "${BLUE}=== BATS Test Runner Configuration ===${NC}"
    echo "BATS Binary:     ${BATS_BIN}"
    echo "Tests Directory: ${BATS_TESTS_DIR}"
    echo "Results Directory: ${RESULTS_DIR}"
    echo "Parallel Jobs:   ${PARALLEL_JOBS}"
    echo "Output Format:   ${OUTPUT_FORMAT}"
    echo "Verbose:         ${VERBOSE}"
    echo "Timeout:         ${TIMEOUT}s"
    [[ -n "${FILTER_PATTERN}" ]] && echo "Filter:          ${FILTER_PATTERN}"
    echo -e "${BLUE}======================================${NC}\n"
}

# Discover BATS test files
discover_tests() {
    local test_files=()

    if [[ -n "${FILTER_PATTERN}" ]]; then
        # Filter based on pattern
        IFS=',' read -ra PATTERNS <<< "${FILTER_PATTERN}"
        for pattern in "${PATTERNS[@]}"; do
            pattern=$(echo "${pattern}" | xargs)  # trim whitespace
            local files=$(find "${BATS_TESTS_DIR}" -name "${pattern}*.bats" -type f | sort)
            if [[ -n "${files}" ]]; then
                test_files+=($files)
            fi
        done
    else
        # All test files
        test_files=($(find "${BATS_TESTS_DIR}" -name "*.bats" -type f | sort))
    fi

    echo "${test_files[@]}"
}

# Run single BATS test file
run_single_test() {
    local test_file="$1"
    local test_name=$(basename "${test_file}" .bats)
    local start_time=$(date +%s)

    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} Running: ${test_name}"

    # Prepare log file
    local log_file="${RESULTS_DIR}/logs/${test_name}.log"

    # Run BATS test with timeout
    local exit_code=0
    if timeout "${TIMEOUT}" "${BATS_BIN}" \
        --tap \
        --timing \
        "${test_file}" > "${RESULTS_DIR}/tap/${test_name}.tap" 2> "${log_file}"; then
        exit_code=0
    else
        exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Generate JUnit XML if requested
    if [[ "${OUTPUT_FORMAT}" == "junit" ]] || [[ "${OUTPUT_FORMAT}" == "both" ]]; then
        tap_to_junit "${RESULTS_DIR}/tap/${test_name}.tap" \
                     "${RESULTS_DIR}/junit/${test_name}.xml" \
                     "${test_name}" \
                     "${duration}"
    fi

    # Print result
    if [[ ${exit_code} -eq 0 ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} ${test_name} (${duration}s)"
        return 0
    elif [[ ${exit_code} -eq 124 ]]; then
        echo -e "${YELLOW}[TIMEOUT]${NC} ${test_name} (${duration}s)"
        return 1
    else
        echo -e "${RED}[FAIL]${NC} ${test_name} (${duration}s)"
        if [[ "${VERBOSE}" == "true" ]]; then
            echo "  Log: ${log_file}"
            tail -n 10 "${log_file}" | sed 's/^/    /'
        fi
        return 1
    fi
}

# Convert TAP to JUnit XML
tap_to_junit() {
    local tap_file="$1"
    local junit_file="$2"
    local test_name="$3"
    local duration="$4"

    # Parse TAP output and generate JUnit XML
    local total=0
    local failures=0
    local skipped=0
    local test_cases=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^ok\ ([0-9]+)\ -\ (.*)$ ]]; then
            total=$((total + 1))
            local test_case_name="${BASH_REMATCH[2]}"
            test_cases+="    <testcase classname=\"${test_name}\" name=\"${test_case_name}\" time=\"0\"/>\n"
        elif [[ "$line" =~ ^not\ ok\ ([0-9]+)\ -\ (.*)$ ]]; then
            total=$((total + 1))
            failures=$((failures + 1))
            local test_case_name="${BASH_REMATCH[2]}"
            test_cases+="    <testcase classname=\"${test_name}\" name=\"${test_case_name}\" time=\"0\">\n"
            test_cases+="      <failure message=\"Test failed\">Test case failed</failure>\n"
            test_cases+="    </testcase>\n"
        elif [[ "$line" =~ ^ok\ ([0-9]+)\ -\ (.*)\ #\ SKIP ]]; then
            total=$((total + 1))
            skipped=$((skipped + 1))
            local test_case_name="${BASH_REMATCH[2]}"
            test_cases+="    <testcase classname=\"${test_name}\" name=\"${test_case_name}\" time=\"0\">\n"
            test_cases+="      <skipped/>\n"
            test_cases+="    </testcase>\n"
        fi
    done < "${tap_file}"

    # Generate JUnit XML
    cat > "${junit_file}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="${test_name}" tests="${total}" failures="${failures}" skipped="${skipped}" time="${duration}">
$(echo -e "${test_cases}")
  </testsuite>
</testsuites>
EOF
}

# Generate aggregate report
generate_aggregate_report() {
    local test_files=("$@")
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local timeout_tests=0
    local total_duration=0

    echo -e "\n${BLUE}=== Aggregating Test Results ===${NC}"

    # Parse all TAP files
    for tap_file in "${RESULTS_DIR}"/tap/*.tap; do
        if [[ -f "${tap_file}" ]]; then
            local passed=$(grep -c "^ok " "${tap_file}" || true)
            local failed=$(grep -c "^not ok " "${tap_file}" || true)
            total_tests=$((total_tests + passed + failed))
            passed_tests=$((passed_tests + passed))
            failed_tests=$((failed_tests + failed))
        fi
    done

    # Calculate statistics
    local pass_rate=0
    if [[ ${total_tests} -gt 0 ]]; then
        pass_rate=$(awk "BEGIN {printf \"%.2f\", (${passed_tests}/${total_tests})*100}")
    fi

    # Generate JSON report
    cat > "${RESULTS_DIR}/aggregate-report.json" <<EOF
{
  "test_run": {
    "timestamp": "$(date -Iseconds)",
    "parallel_jobs": ${PARALLEL_JOBS},
    "timeout": ${TIMEOUT}
  },
  "summary": {
    "total": ${total_tests},
    "passed": ${passed_tests},
    "failed": ${failed_tests},
    "timeout": ${timeout_tests},
    "pass_rate": ${pass_rate}
  },
  "results_directory": "${RESULTS_DIR}"
}
EOF

    # Print summary
    echo -e "\n${BLUE}=== Test Summary ===${NC}"
    echo -e "Total Tests:  ${total_tests}"
    echo -e "Passed:       ${GREEN}${passed_tests}${NC}"
    echo -e "Failed:       ${RED}${failed_tests}${NC}"
    echo -e "Pass Rate:    ${pass_rate}%"
    echo -e "\nResults saved to: ${RESULTS_DIR}"

    # Return non-zero if any tests failed
    [[ ${failed_tests} -eq 0 ]]
}

# Main execution
main() {
    print_config

    # Discover test files
    local test_files=($(discover_tests))

    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No test files found${NC}"
        exit 1
    fi

    echo -e "Found ${#test_files[@]} test file(s) to run\n"

    # Run tests in parallel using GNU parallel if available
    local failed_count=0
    if command -v parallel &> /dev/null; then
        echo -e "${BLUE}Running tests in parallel (${PARALLEL_JOBS} jobs)...${NC}\n"
        export -f run_single_test tap_to_junit
        export BATS_BIN RESULTS_DIR OUTPUT_FORMAT VERBOSE TIMEOUT RED GREEN YELLOW BLUE NC

        if ! printf "%s\n" "${test_files[@]}" | \
            parallel --jobs "${PARALLEL_JOBS}" --line-buffer run_single_test {}; then
            failed_count=$?
        fi
    else
        echo -e "${YELLOW}Warning: GNU parallel not found, running sequentially${NC}\n"
        for test_file in "${test_files[@]}"; do
            if ! run_single_test "${test_file}"; then
                failed_count=$((failed_count + 1))
            fi
        done
    fi

    # Generate aggregate report
    generate_aggregate_report "${test_files[@]}"

    local exit_code=$?
    if [[ ${exit_code} -eq 0 ]]; then
        echo -e "\n${GREEN}✓ All tests passed!${NC}"
    else
        echo -e "\n${RED}✗ Some tests failed${NC}"
    fi

    exit ${exit_code}
}

# Run main function
main "$@"
