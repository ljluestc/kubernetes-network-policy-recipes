#!/bin/bash
# Conditional Test Execution Engine
# Determines which tests should run based on environment capabilities

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/cloud-detection.sh" ]]; then
    source "$SCRIPT_DIR/cloud-detection.sh"
fi
if [[ -f "$SCRIPT_DIR/feature-matrix.sh" ]]; then
    source "$SCRIPT_DIR/feature-matrix.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Determine if a test should run based on environment capabilities
should_run_test() {
    local test_id="$1"
    local provider="${2:-$(detect_cloud_provider)}"
    local cni="${3:-$(detect_cni_plugin)}"
    local reason=""

    case "$test_id" in
        00)
            # Cluster setup - always run
            return 0
            ;;
        01|02|02a)
            # Deny-all and allow-all policies
            if is_recipe_supported "$test_id" "$cni"; then
                return 0
            else
                reason="CNI $cni does not support basic ingress policies"
                echo "$reason" >&2
                return 1
            fi
            ;;
        03|04|05|06)
            # Namespace-based policies
            if is_recipe_supported "$test_id" "$cni"; then
                return 0
            else
                reason="CNI $cni does not support namespace selectors"
                echo "$reason" >&2
                return 1
            fi
            ;;
        07)
            # Pod selector policies
            if is_recipe_supported "$test_id" "$cni"; then
                return 0
            else
                reason="CNI $cni does not support pod selectors"
                echo "$reason" >&2
                return 1
            fi
            ;;
        08)
            # External traffic - needs real LoadBalancer
            if [[ "$provider" =~ ^(gke|eks|aks)$ ]]; then
                if is_recipe_supported "$test_id" "$cni"; then
                    return 0
                else
                    reason="CNI $cni does not support ipBlock rules"
                    echo "$reason" >&2
                    return 1
                fi
            else
                reason="Recipe 08 requires cloud provider with LoadBalancer support (provider: $provider)"
                echo "$reason" >&2
                return 1
            fi
            ;;
        09|10)
            # Port-based policies
            if is_recipe_supported "$test_id" "$cni"; then
                return 0
            else
                reason="CNI $cni does not support port-based policies"
                echo "$reason" >&2
                return 1
            fi
            ;;
        11|12)
            # Egress policies
            if is_recipe_supported "$test_id" "$cni"; then
                return 0
            else
                reason="CNI $cni does not support egress policies"
                echo "$reason" >&2
                return 1
            fi
            ;;
        13)
            # Egress to specific pods
            if is_recipe_supported "$test_id" "$cni"; then
                return 0
            else
                reason="CNI $cni does not support egress pod selectors"
                echo "$reason" >&2
                return 1
            fi
            ;;
        14)
            # External egress - needs proper networking
            if [[ "$cni" != "unknown" ]]; then
                if is_recipe_supported "$test_id" "$cni"; then
                    return 0
                else
                    reason="CNI $cni does not support external egress policies"
                    echo "$reason" >&2
                    return 1
                fi
            else
                reason="Cannot determine CNI plugin for recipe 14"
                echo "$reason" >&2
                return 1
            fi
            ;;
        *)
            # Unknown recipe, run by default
            warn "Unknown recipe ID: $test_id, running by default"
            return 0
            ;;
    esac
}

# Get provider-specific timeout
get_provider_timeout() {
    local provider="${1:-$(detect_cloud_provider)}"

    case "$provider" in
        gke|eks|aks)
            echo "120"  # Cloud providers need more time for resource provisioning
            ;;
        kind|k3s|microk8s)
            echo "60"   # Local clusters are faster
            ;;
        minikube)
            echo "90"   # Minikube can be slower due to VM overhead
            ;;
        *)
            echo "90"   # Default timeout
            ;;
    esac
}

# Get provider-specific retry count
get_provider_retry_count() {
    local provider="${1:-$(detect_cloud_provider)}"

    case "$provider" in
        gke|eks|aks)
            echo "5"    # Cloud providers may need more retries
            ;;
        kind|k3s|microk8s|minikube)
            echo "3"    # Local clusters are more stable
            ;;
        *)
            echo "3"    # Default retry count
            ;;
    esac
}

# Get provider-specific polling interval
get_provider_poll_interval() {
    local provider="${1:-$(detect_cloud_provider)}"

    case "$provider" in
        gke|eks|aks)
            echo "10"   # Cloud providers may take longer to apply changes
            ;;
        kind|k3s|microk8s|minikube)
            echo "5"    # Local clusters apply changes quickly
            ;;
        *)
            echo "5"    # Default polling interval
            ;;
    esac
}

# Check if test requires specific capabilities
check_test_requirements() {
    local test_id="$1"
    local provider="${2:-$(detect_cloud_provider)}"
    local cni="${3:-$(detect_cni_plugin)}"
    local missing_requirements=()

    case "$test_id" in
        08)
            # External traffic requires LoadBalancer
            if [[ ! "$provider" =~ ^(gke|eks|aks)$ ]]; then
                missing_requirements+=("LoadBalancer service type support")
            fi
            ;;
        14)
            # External egress requires external connectivity
            if ! kubectl run test-connectivity-check --image=busybox --restart=Never --rm -i --timeout=10s -- wget -O- -q https://www.google.com &>/dev/null; then
                missing_requirements+=("External network connectivity")
            fi
            ;;
    esac

    if [[ ${#missing_requirements[@]} -gt 0 ]]; then
        echo "Missing requirements for test $test_id:"
        printf '  - %s\n' "${missing_requirements[@]}"
        return 1
    fi

    return 0
}

# Get list of runnable tests for current environment
get_runnable_tests() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"
    local all_tests=("00" "01" "02" "02a" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12" "13" "14")
    local runnable=()

    for test in "${all_tests[@]}"; do
        if should_run_test "$test" "$provider" "$cni" 2>/dev/null; then
            runnable+=("$test")
        fi
    done

    echo "${runnable[@]}"
}

# Get list of skipped tests for current environment
get_skipped_tests() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"
    local all_tests=("00" "01" "02" "02a" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12" "13" "14")
    local skipped=()

    for test in "${all_tests[@]}"; do
        if ! should_run_test "$test" "$provider" "$cni" 2>/dev/null; then
            skipped+=("$test")
        fi
    done

    echo "${skipped[@]}"
}

# Generate test execution plan
generate_test_plan() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"

    local runnable=($(get_runnable_tests "$provider" "$cni"))
    local skipped=($(get_skipped_tests "$provider" "$cni"))
    local timeout=$(get_provider_timeout "$provider")
    local retries=$(get_provider_retry_count "$provider")
    local poll_interval=$(get_provider_poll_interval "$provider")

    # Build runnable tests JSON array
    local runnable_json="["
    local first=true
    for test in "${runnable[@]}"; do
        [[ "$first" != "true" ]] && runnable_json+=","
        first=false
        runnable_json+="\"$test\""
    done
    runnable_json+="]"

    # Build skipped tests JSON array
    local skipped_json="["
    first=true
    for test in "${skipped[@]}"; do
        [[ "$first" != "true" ]] && skipped_json+=","
        first=false
        skipped_json+="\"$test\""
    done
    skipped_json+="]"

    cat <<EOF
{
  "environment": {
    "provider": "$provider",
    "cni": "$cni"
  },
  "execution_config": {
    "timeout_seconds": $timeout,
    "retry_count": $retries,
    "poll_interval_seconds": $poll_interval
  },
  "test_plan": {
    "runnable_tests": $runnable_json,
    "skipped_tests": $skipped_json,
    "total_runnable": ${#runnable[@]},
    "total_skipped": ${#skipped[@]}
  },
  "generated_at": "$(date -Iseconds)"
}
EOF
}

# Print test execution summary
print_test_summary() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"

    local runnable=($(get_runnable_tests "$provider" "$cni"))
    local skipped=($(get_skipped_tests "$provider" "$cni"))

    echo ""
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}Test Execution Summary${NC}"
    echo -e "${GREEN}===============================================${NC}"
    echo -e "Provider: ${CYAN}$provider${NC}"
    echo -e "CNI:      ${CYAN}$cni${NC}"
    echo ""
    echo -e "${GREEN}Runnable Tests (${#runnable[@]}):${NC}"
    for test in "${runnable[@]}"; do
        echo -e "  ${GREEN}✓${NC} Recipe $test"
    done

    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Skipped Tests (${#skipped[@]}):${NC}"
        for test in "${skipped[@]}"; do
            echo -e "  ${YELLOW}⊘${NC} Recipe $test"
        done
    fi
    echo -e "${GREEN}===============================================${NC}"
    echo ""
}

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --should-run)
            test_id="${2:-}"
            if [[ -z "$test_id" ]]; then
                echo "Usage: $0 --should-run <test_id> [provider] [cni]"
                exit 1
            fi
            provider="${3:-$(detect_cloud_provider)}"
            cni="${4:-$(detect_cni_plugin)}"
            if should_run_test "$test_id" "$provider" "$cni"; then
                echo "Test $test_id should run on $provider with $cni"
                exit 0
            else
                echo "Test $test_id should be skipped on $provider with $cni"
                exit 1
            fi
            ;;
        --plan)
            generate_test_plan
            ;;
        --summary)
            print_test_summary
            ;;
        --runnable)
            provider="${2:-$(detect_cloud_provider)}"
            cni="${3:-$(detect_cni_plugin)}"
            get_runnable_tests "$provider" "$cni"
            ;;
        --skipped)
            provider="${2:-$(detect_cloud_provider)}"
            cni="${3:-$(detect_cni_plugin)}"
            get_skipped_tests "$provider" "$cni"
            ;;
        *)
            echo "Conditional Test Execution Engine"
            echo ""
            echo "Usage:"
            echo "  $0 --should-run <test_id> [provider] [cni]  Check if test should run"
            echo "  $0 --plan                                    Generate test execution plan (JSON)"
            echo "  $0 --summary                                 Print test execution summary"
            echo "  $0 --runnable [provider] [cni]              List runnable tests"
            echo "  $0 --skipped [provider] [cni]               List skipped tests"
            echo ""
            echo "Or source this script to use functions:"
            echo "  source $0"
            echo "  should_run_test \"08\" \"\$(detect_cloud_provider)\" \"\$(detect_cni_plugin)\""
            echo "  plan=\$(generate_test_plan)"
            ;;
    esac
fi
