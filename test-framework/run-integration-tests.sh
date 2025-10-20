#!/usr/bin/env bash
# Comprehensive Integration Test Runner for Kubernetes Network Policy Recipes
# Executes all integration test scenarios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="${SCRIPT_DIR}/integration-tests/scenarios"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Test counters
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# Source all scenario files
for scenario_file in "${INTEGRATION_DIR}"/*.sh; do
    if [[ -f "$scenario_file" ]]; then
        source "$scenario_file"
    fi
done

# Run a test and track results
run_test() {
    local test_name="$1"
    TOTAL=$((TOTAL + 1))

    if $test_name; then
        PASSED=$((PASSED + 1))
        return 0
    else
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Pre-flight checks
preflight_checks() {
    log "Running pre-flight checks..."

    # Check kubectl is available
    if ! command -v kubectl &>/dev/null; then
        error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check for existing test namespaces
    local test_namespaces=$(kubectl get namespaces -o name | grep -E 'integration-.*-[0-9]+$' || true)
    if [[ -n "$test_namespaces" ]]; then
        warn "Found existing test namespaces from previous runs"
        echo "$test_namespaces"
        read -p "Clean up? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$test_namespaces" | xargs -r kubectl delete --wait=false 2>/dev/null || true
            sleep 3
        fi
    fi

    success "Pre-flight checks passed"
}

# Main test execution
main() {
    echo "==============================================="
    echo "  Integration Tests for Network Policies"
    echo "==============================================="
    echo ""

    preflight_checks
    echo ""

    log "Starting integration test suite..."
    echo ""

    # Multi-policy combination tests
    echo "${CYAN}=== Multi-Policy Combinations ===${NC}"
    run_test test_deny_all_plus_selective_allow
    run_test test_multiple_ingress_rules
    run_test test_policy_priority_and_precedence
    echo ""

    # Three-tier application tests
    echo "${CYAN}=== Three-Tier Applications ===${NC}"
    run_test test_three_tier_application
    run_test test_three_tier_with_monitoring
    run_test test_three_tier_port_restrictions
    echo ""

    # Cross-namespace tests
    echo "${CYAN}=== Cross-Namespace Communication ===${NC}"
    run_test test_cross_namespace_policy_precedence
    run_test test_namespace_isolation
    run_test test_selective_cross_namespace_access
    echo ""

    # Microservices tests
    echo "${CYAN}=== Microservices Patterns ===${NC}"
    run_test test_microservices_service_mesh
    run_test test_microservices_sidecar_pattern
    run_test test_microservices_canary_deployment
    echo ""

    # Policy conflict tests
    echo "${CYAN}=== Policy Conflicts & Precedence ===${NC}"
    run_test test_overlapping_selectors
    run_test test_ingress_egress_conflict
    run_test test_policy_order_independence
    run_test test_empty_selector_behavior
    echo ""

    # Performance tests
    echo "${CYAN}=== Performance & Scale ===${NC}"
    run_test test_many_policies_performance
    run_test test_complex_selector_performance
    run_test test_policy_update_latency
    run_test test_namespace_with_many_pods
    echo ""

    # Failure recovery tests
    echo "${CYAN}=== Failure & Recovery ===${NC}"
    run_test test_pod_restart_policy_persistence
    run_test test_invalid_policy_rejection
    run_test test_policy_deletion_recovery
    run_test test_namespace_deletion_cleanup
    run_test test_concurrent_policy_updates
    echo ""

    # Summary
    echo "==============================================="
    echo "${CYAN}  Integration Test Summary${NC}"
    echo "==============================================="
    echo "Total Tests:  $TOTAL"
    echo -e "${GREEN}Passed:       $PASSED${NC}"
    echo -e "${RED}Failed:       $FAILED${NC}"

    if [[ $FAILED -eq 0 ]]; then
        echo ""
        success "All integration tests passed!"
        echo ""
        echo "Coverage breakdown:"
        echo "  - Multi-policy combinations: 3 tests"
        echo "  - Three-tier applications: 3 tests"
        echo "  - Cross-namespace: 3 tests"
        echo "  - Microservices patterns: 3 tests"
        echo "  - Policy conflicts: 4 tests"
        echo "  - Performance: 4 tests"
        echo "  - Failure recovery: 5 tests"
        echo "  ${GREEN}Total: 25 integration tests${NC}"
        exit 0
    else
        echo ""
        error "Some integration tests failed"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    warn "Cleaning up test resources..."
    kubectl get namespaces -o name | grep -E 'integration-.*-[0-9]+$' | xargs -r kubectl delete --wait=false 2>/dev/null || true
}

# Register cleanup on exit
trap cleanup EXIT

# Run main
main "$@"
