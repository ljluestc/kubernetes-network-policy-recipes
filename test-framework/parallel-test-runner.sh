#!/bin/bash
# Parallel Test Runner for Kubernetes Network Policy Recipes
# Executes multiple network policy tests concurrently with resource isolation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/results}"
MAX_WORKERS="${MAX_WORKERS:-4}"
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
NAMESPACE_PREFIX="np-test"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Source multi-cloud libraries
if [[ -f "$SCRIPT_DIR/lib/cloud-detection.sh" ]]; then
    source "$SCRIPT_DIR/lib/cloud-detection.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/feature-matrix.sh" ]]; then
    source "$SCRIPT_DIR/lib/feature-matrix.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/provider-config.sh" ]]; then
    source "$SCRIPT_DIR/lib/provider-config.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Parallel test runner for Kubernetes Network Policy recipes

OPTIONS:
    -w, --workers NUM          Max parallel workers (default: auto-detect)
    -t, --timeout SECONDS      Test timeout (default: auto-detect)
    -r, --results-dir PATH     Results directory (default: ./results)
    -f, --filter PATTERN       Filter tests by pattern (e.g., "01,02,03")
    -j, --json                 Output JSON results only
    -v, --verbose              Verbose output
    --skip-unsupported         Skip tests unsupported by current CNI
    --detect                   Show environment detection info and exit
    -h, --help                 Show this help message

EXAMPLES:
    $0                         # Run all tests with auto-detected settings
    $0 -w 8                    # Run with 8 parallel workers
    $0 -f "01,02,09"           # Run only specific tests
    $0 --detect                # Show detected environment info
    $0 --skip-unsupported      # Skip unsupported recipes for current CNI
    $0 -j > results.json       # Output JSON results

MULTI-CLOUD SUPPORT:
    Automatically detects: GKE, EKS, AKS, kind, minikube, k3s, microk8s
    Automatically detects CNI: Calico, Cilium, Weave, Flannel, VPC CNI, Azure CNI
    Auto-adjusts timeout and worker count based on provider

EOF
    exit 1
}

# Initialize results directory
init_results_dir() {
    mkdir -p "$RESULTS_DIR"
    log "Results directory: $RESULTS_DIR"
}

# Discover all recipe test files
discover_recipes() {
    local filter="$1"
    local recipes=()

    # Find all numbered markdown files (recipes)
    while IFS= read -r file; do
        local basename=$(basename "$file" .md)
        local recipe_id=$(echo "$basename" | grep -oP '^\d+[a-z]?')

        # Skip 00 (cluster setup, not a test)
        [[ "$recipe_id" == "00" ]] && continue

        # Apply filter if specified
        if [[ -n "$filter" ]]; then
            if ! echo ",$filter," | grep -q ",$recipe_id,"; then
                continue
            fi
        fi

        recipes+=("$recipe_id")
    done < <(find "$PROJECT_ROOT" -maxdepth 1 -name '[0-9][0-9]*.md' | sort)

    echo "${recipes[@]}"
}

# Generate unique namespace for test
get_test_namespace() {
    local recipe_id="$1"
    echo "${NAMESPACE_PREFIX}-${recipe_id}-${TIMESTAMP}-$$"
}

# Create test namespace with labels
create_test_namespace() {
    local namespace="$1"
    local recipe_id="$2"

    kubectl create namespace "$namespace" 2>/dev/null || true
    kubectl label namespace "$namespace" \
        "test-runner=parallel" \
        "recipe-id=$recipe_id" \
        "test-run=$TIMESTAMP" \
        --overwrite >/dev/null 2>&1
}

# Cleanup test namespace
cleanup_namespace() {
    local namespace="$1"
    kubectl delete namespace "$namespace" --ignore-not-found=true --wait=false &>/dev/null || true
}

# Execute a single test with timeout and isolation
run_single_test() {
    local recipe_id="$1"
    local result_file="$RESULTS_DIR/test-${recipe_id}.json"

    local start_time=$(date +%s)
    local namespace=$(get_test_namespace "$recipe_id")
    local test_status="FAIL"
    local test_output=""
    local error_message=""

    # Create isolated namespace
    create_test_namespace "$namespace" "$recipe_id"

    # Source test library
    source "$SCRIPT_DIR/lib/test-functions.sh"

    # Run test with timeout
    if timeout "$TEST_TIMEOUT" bash -c "
        export TEST_NAMESPACE='$namespace'
        export RECIPE_ID='$recipe_id'
        test_recipe_$recipe_id
    " >/tmp/test-${recipe_id}-$$.log 2>&1; then
        test_status="PASS"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            error_message="Test timed out after ${TEST_TIMEOUT}s"
            test_status="TIMEOUT"
        else
            error_message="Test failed with exit code $exit_code"
            test_status="FAIL"
        fi
    fi

    test_output=$(cat /tmp/test-${recipe_id}-$$.log 2>/dev/null || echo "")
    rm -f /tmp/test-${recipe_id}-$$.log

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Cleanup namespace
    cleanup_namespace "$namespace"

    # Generate JSON result
    cat > "$result_file" <<EOF
{
  "recipe_id": "$recipe_id",
  "status": "$test_status",
  "duration_seconds": $duration,
  "namespace": "$namespace",
  "timestamp": "$(date -Iseconds)",
  "timeout_seconds": $TEST_TIMEOUT,
  "error_message": $(echo "$error_message" | jq -Rs .),
  "output": $(echo "$test_output" | jq -Rs .)
}
EOF

    # Output status to stderr for progress tracking
    if [[ "$test_status" == "PASS" ]]; then
        success "Recipe $recipe_id: PASSED (${duration}s)"
    else
        error "Recipe $recipe_id: $test_status (${duration}s)"
    fi

    echo "$result_file"
}

# Aggregate test results
aggregate_results() {
    local results_files=("$@")
    local total=0
    local passed=0
    local failed=0
    local timeout=0
    local total_duration=0

    # Detect environment for report metadata
    local env_provider="unknown"
    local env_cni="unknown"
    local env_k8s_version="unknown"
    if type detect_cloud_provider &>/dev/null; then
        env_provider=$(detect_cloud_provider 2>/dev/null || echo "unknown")
        env_cni=$(detect_cni_plugin 2>/dev/null || echo "unknown")
        env_k8s_version=$(get_k8s_version 2>/dev/null || echo "unknown")
    fi

    # Start JSON array
    echo "{"
    echo '  "test_run": {'
    echo "    \"timestamp\": \"$(date -Iseconds)\","
    echo "    \"workers\": $MAX_WORKERS,"
    echo "    \"timeout\": $TEST_TIMEOUT"
    echo '  },'
    echo '  "environment": {'
    echo "    \"provider\": \"$env_provider\","
    echo "    \"cni\": \"$env_cni\","
    echo "    \"kubernetes_version\": \"$env_k8s_version\""
    echo '  },'
    echo '  "results": ['

    local first=true
    for result_file in "${results_files[@]}"; do
        if [[ -f "$result_file" ]]; then
            [[ "$first" != "true" ]] && echo "    ,"
            first=false

            cat "$result_file" | sed 's/^/    /'

            # Count results
            local status=$(jq -r '.status' "$result_file")
            local duration=$(jq -r '.duration_seconds' "$result_file")

            ((total++))
            ((total_duration += duration))

            case "$status" in
                PASS) ((passed++)) ;;
                TIMEOUT) ((timeout++)) ;;
                *) ((failed++)) ;;
            esac
        fi
    done

    echo ""
    echo '  ],'
    echo '  "summary": {'
    echo "    \"total\": $total,"
    echo "    \"passed\": $passed,"
    echo "    \"failed\": $failed,"
    echo "    \"timeout\": $timeout,"
    echo "    \"total_duration_seconds\": $total_duration,"
    echo "    \"pass_rate\": $(echo "scale=2; $passed * 100 / $total" | bc 2>/dev/null || echo 0)"
    echo '  }'
    echo "}"
}

# Main execution
main() {
    local filter=""
    local json_only=false
    local verbose=false
    local skip_unsupported=false
    local show_detect=false
    local auto_detect_workers=true
    local auto_detect_timeout=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--workers) MAX_WORKERS="$2"; auto_detect_workers=false; shift 2 ;;
            -t|--timeout) TEST_TIMEOUT="$2"; auto_detect_timeout=false; shift 2 ;;
            -r|--results-dir) RESULTS_DIR="$2"; shift 2 ;;
            -f|--filter) filter="$2"; shift 2 ;;
            -j|--json) json_only=true; shift ;;
            -v|--verbose) verbose=true; set -x; shift ;;
            --skip-unsupported) skip_unsupported=true; shift ;;
            --detect) show_detect=true; shift ;;
            -h|--help) usage ;;
            *) error "Unknown option: $1"; usage ;;
        esac
    done

    # Check dependencies
    command -v kubectl >/dev/null || { error "kubectl not found"; exit 1; }
    command -v jq >/dev/null || { error "jq not found (required for JSON processing)"; exit 1; }
    command -v parallel >/dev/null || { error "GNU parallel not found"; exit 1; }

    # Detect environment if functions are available
    local provider="unknown"
    local cni="unknown"
    if type detect_cloud_provider &>/dev/null; then
        provider=$(detect_cloud_provider)
        cni=$(detect_cni_plugin)

        # Auto-detect settings if not manually specified
        if [[ "$auto_detect_timeout" == "true" ]] && type get_provider_timeout &>/dev/null; then
            TEST_TIMEOUT=$(get_provider_timeout "$provider")
        fi
        if [[ "$auto_detect_workers" == "true" ]] && type get_provider_workers &>/dev/null; then
            MAX_WORKERS=$(get_provider_workers "$provider")
        fi

        # Apply provider-specific configuration
        if type apply_provider_config &>/dev/null; then
            apply_provider_config "$provider" &>/dev/null
        fi
    fi

    # Show detection info and exit if requested
    if [[ "$show_detect" == "true" ]]; then
        if type generate_environment_report &>/dev/null; then
            echo "=== Environment Detection ==="
            echo ""
            generate_environment_report | jq .
            echo ""
        fi
        if type generate_compatibility_report &>/dev/null; then
            echo "=== Compatibility Report ==="
            echo ""
            generate_compatibility_report | jq .
            echo ""
        fi
        exit 0
    fi

    # Validate environment if validation function is available
    if type validate_environment &>/dev/null; then
        if ! validate_environment "$provider" "$cni" &>/dev/null; then
            warn "Environment validation failed. Tests may not run correctly."
        fi
    fi

    init_results_dir

    # Discover recipes to test
    local recipes=($(discover_recipes "$filter"))

    # Filter out unsupported recipes if requested
    if [[ "$skip_unsupported" == "true" ]] && type get_unsupported_recipes &>/dev/null; then
        local unsupported=($(get_unsupported_recipes "$cni"))
        local filtered_recipes=()

        for recipe in "${recipes[@]}"; do
            local is_unsupported=false
            for unsupp in "${unsupported[@]}"; do
                if [[ "$recipe" == "$unsupp" ]]; then
                    is_unsupported=true
                    break
                fi
            done
            if [[ "$is_unsupported" == "false" ]]; then
                filtered_recipes+=("$recipe")
            else
                [[ "$json_only" != "true" ]] && warn "Skipping unsupported recipe $recipe for CNI: $cni"
            fi
        done

        recipes=("${filtered_recipes[@]}")
    fi

    if [[ ${#recipes[@]} -eq 0 ]]; then
        error "No recipes found to test"
        exit 1
    fi

    if [[ "$json_only" != "true" ]]; then
        log "Found ${#recipes[@]} recipes to test: ${recipes[*]}"
        if [[ "$provider" != "unknown" ]]; then
            info "Detected environment: $provider with $cni CNI"
        fi
        log "Running tests with $MAX_WORKERS parallel workers (timeout: ${TEST_TIMEOUT}s)..."
    fi

    # Run tests in parallel using GNU parallel
    local result_files=()
    while IFS= read -r result_file; do
        result_files+=("$result_file")
    done < <(
        printf '%s\n' "${recipes[@]}" | \
        parallel -j "$MAX_WORKERS" --line-buffer \
            "$0" --run-single-test {} "$RESULTS_DIR"
    )

    # Generate aggregated results
    local aggregate_file="$RESULTS_DIR/aggregate-${TIMESTAMP}.json"
    aggregate_results "${result_files[@]}" > "$aggregate_file"

    if [[ "$json_only" == "true" ]]; then
        cat "$aggregate_file"
    else
        log "Results saved to: $aggregate_file"

        # Generate HTML report
        if [[ -f "$SCRIPT_DIR/lib/report-generator.sh" ]]; then
            log "Generating HTML report..."
            "$SCRIPT_DIR/lib/report-generator.sh" "$aggregate_file" "$RESULTS_DIR/html/report-${TIMESTAMP}.html" 2>&1 | grep -v "^\[" || true
        fi

        # Archive for historical comparison
        if [[ -f "$SCRIPT_DIR/lib/historical-comparison.sh" ]]; then
            "$SCRIPT_DIR/lib/historical-comparison.sh" archive "$aggregate_file" 2>&1 | grep -v "^\[" || true
        fi

        # Display summary
        local summary=$(jq -r '.summary' "$aggregate_file")
        echo ""
        success "===== Test Summary ====="
        jq -r '.summary |
            "Total: \(.total)\n" +
            "Passed: \(.passed)\n" +
            "Failed: \(.failed)\n" +
            "Timeout: \(.timeout)\n" +
            "Pass Rate: \(.pass_rate)%\n" +
            "Total Duration: \(.total_duration_seconds)s"
        ' "$aggregate_file"
    fi

    # Exit with appropriate code
    local failed_count=$(jq -r '.summary.failed + .summary.timeout' "$aggregate_file")
    exit "$failed_count"
}

# Handle internal call for running single test (called by GNU parallel)
if [[ "${1:-}" == "--run-single-test" ]]; then
    run_single_test "$2"
    exit 0
fi

main "$@"
