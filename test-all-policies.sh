#!/bin/bash
# Comprehensive Test Suite for Kubernetes Network Policy Recipes
# Tests each network policy to verify it works as expected

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Logging
log() { echo -e "${BLUE}[TEST]${NC} $*"; }
pass() { echo -e "${GREEN}✓ PASS${NC} $*"; ((TESTS_PASSED++)); }
fail() { echo -e "${RED}✗ FAIL${NC} $*"; ((TESTS_FAILED++)); }
skip() { echo -e "${YELLOW}⊘ SKIP${NC} $*"; ((TESTS_SKIPPED++)); }

# Configuration
NAMESPACE="policy-demo"
TIMEOUT=30

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Test all Kubernetes Network Policy recipes

OPTIONS:
    -n, --namespace NAMESPACE   Test namespace (default: policy-demo)
    -t, --timeout SECONDS      Test timeout (default: 30)
    -v, --verbose              Verbose output
    -h, --help                 Show this help message

EOF
    exit 1
}

# Cleanup function
cleanup() {
    log "Cleaning up test resources..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true &>/dev/null || true
}

# Create test namespace
setup() {
    log "Setting up test environment..."

    # Create namespace
    kubectl create namespace "$NAMESPACE" 2>/dev/null || true

    # Deploy test pods
    kubectl run -n "$NAMESPACE" web --image=nginx --labels="app=web" &>/dev/null || true
    kubectl run -n "$NAMESPACE" api --image=nginx --labels="app=api,role=backend" &>/dev/null || true
    kubectl run -n "$NAMESPACE" db --image=nginx --labels="app=db,role=backend" &>/dev/null || true

    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -n "$NAMESPACE" --all --timeout=60s &>/dev/null || {
        fail "Failed to start test pods"
        return 1
    }

    pass "Test environment ready"
}

# Test NP-01: Deny all traffic to an application
test_np01() {
    log "Testing NP-01: Deny all traffic to an application"

    # Apply policy
    kubectl apply -n "$NAMESPACE" -f - <<EOF >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-all
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
EOF

    # Test: Traffic should be blocked
    if kubectl exec -n "$NAMESPACE" api -- timeout 5 wget -q -O- http://web 2>/dev/null; then
        fail "NP-01: Traffic was NOT blocked (expected to be denied)"
    else
        pass "NP-01: Traffic correctly blocked to web pod"
    fi

    kubectl delete networkpolicy -n "$NAMESPACE" web-deny-all &>/dev/null
}

# Test NP-02: Limit traffic to an application
test_np02() {
    log "Testing NP-02: Limit traffic to an application"

    # Apply policy allowing only from api pod
    kubectl apply -n "$NAMESPACE" -f - <<EOF >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-api
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
EOF

    sleep 3

    # Test: Traffic from api should succeed
    if kubectl exec -n "$NAMESPACE" api -- timeout 5 wget -q -O- http://web 2>/dev/null >/dev/null; then
        pass "NP-02: Traffic from api pod allowed"
    else
        fail "NP-02: Traffic from api pod was blocked (should be allowed)"
    fi

    # Test: Traffic from db should be blocked
    if kubectl exec -n "$NAMESPACE" db -- timeout 5 wget -q -O- http://web 2>/dev/null; then
        fail "NP-02: Traffic from db pod was allowed (should be blocked)"
    else
        pass "NP-02: Traffic from db pod correctly blocked"
    fi

    kubectl delete networkpolicy -n "$NAMESPACE" web-allow-api &>/dev/null
}

# Test NP-09: Allow traffic only to a port
test_np09() {
    log "Testing NP-09: Allow traffic only to a port"

    # Apply policy allowing only port 80
    kubectl apply -n "$NAMESPACE" -f - <<EOF >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-port-80
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 80
EOF

    sleep 3

    # Test: Traffic to port 80 should succeed
    if kubectl exec -n "$NAMESPACE" api -- timeout 5 wget -q -O- http://web:80 2>/dev/null >/dev/null; then
        pass "NP-09: Traffic to port 80 allowed"
    else
        fail "NP-09: Traffic to port 80 was blocked (should be allowed)"
    fi

    kubectl delete networkpolicy -n "$NAMESPACE" web-allow-port-80 &>/dev/null
}

# Test NP-11: Deny egress traffic from an application
test_np11() {
    log "Testing NP-11: Deny egress traffic from an application"

    # Apply deny-all egress policy
    kubectl apply -n "$NAMESPACE" -f - <<EOF >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-all-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    sleep 3

    # Test: Egress should be blocked
    if kubectl exec -n "$NAMESPACE" web -- timeout 5 wget -q -O- http://api 2>/dev/null; then
        fail "NP-11: Egress was allowed (should be blocked)"
    else
        pass "NP-11: Egress correctly blocked from web pod"
    fi

    kubectl delete networkpolicy -n "$NAMESPACE" web-deny-all-egress &>/dev/null
}

# Test cluster connectivity
test_cluster() {
    log "Testing cluster connectivity..."

    if ! kubectl cluster-info &>/dev/null; then
        fail "Cannot connect to Kubernetes cluster"
        return 1
    fi

    pass "Cluster connectivity OK"

    # Check if network policies are supported
    if kubectl api-resources | grep -q networkpolicies; then
        pass "NetworkPolicy API available"
    else
        fail "NetworkPolicy API not available"
        return 1
    fi
}

# Main test runner
main() {
    log "===== Kubernetes Network Policy Test Suite ====="
    echo ""

    # Test cluster
    test_cluster || exit 1

    # Setup test environment
    setup || exit 1

    echo ""
    log "Running network policy tests..."
    echo ""

    # Run tests
    test_np01
    test_np02
    test_np09
    test_np11

    # Cleanup
    echo ""
    cleanup

    # Summary
    echo ""
    log "===== Test Summary ====="
    pass "Passed: $TESTS_PASSED"
    fail "Failed: $TESTS_FAILED"
    skip "Skipped: $TESTS_SKIPPED"
    echo ""

    # Exit code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        log "All tests passed!"
        exit 0
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) set -x; shift ;;
        -h|--help) usage ;;
        *) log "Unknown option: $1"; usage ;;
    esac
done

main
