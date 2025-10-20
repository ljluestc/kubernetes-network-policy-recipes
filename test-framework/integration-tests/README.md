# Integration Tests for Kubernetes Network Policy Recipes

Comprehensive end-to-end integration tests covering complex network policy scenarios, multi-tier applications, and real-world use cases.

## Overview

These integration tests go beyond single-recipe validation to test:

- **Multi-policy combinations**: How multiple policies interact
- **Real-world architectures**: Three-tier apps, microservices patterns
- **Cross-namespace communication**: Namespace isolation and selective access
- **Policy conflicts**: Precedence, overlapping selectors, order independence
- **Performance**: Behavior under load (50+ policies)
- **Failure recovery**: Pod restarts, policy updates, cleanup

## Test Coverage

### Multi-Policy Combinations (3 tests)
- Deny-all + selective allow
- Multiple ingress rules
- Policy priority and precedence

### Three-Tier Applications (3 tests)
- Frontend → Backend → Database isolation
- Three-tier with monitoring sidecar
- Port-specific restrictions

### Cross-Namespace (3 tests)
- Namespace selector policies
- Complete namespace isolation
- Selective cross-namespace access

### Microservices Patterns (3 tests)
- Service mesh communication patterns
- Sidecar proxy pattern
- Canary deployment routing

### Policy Conflicts (4 tests)
- Overlapping selectors (union behavior)
- Ingress vs egress conflicts
- Policy order independence
- Empty selector matching

### Performance & Scale (4 tests)
- 50 policies application time
- Complex selector matching
- Policy update propagation latency
- Namespace with 20 pods

### Failure Recovery (5 tests)
- Pod restart policy persistence
- Invalid policy rejection
- Policy deletion recovery
- Namespace deletion cleanup
- Concurrent policy updates

**Total: 25 integration tests**

## Usage

### Run All Integration Tests

```bash
cd test-framework
./run-integration-tests.sh
```

### Run Individual Test Scenarios

```bash
# Source a scenario file
source integration-tests/scenarios/multi-policy-combination.sh

# Run specific test
test_deny_all_plus_selective_allow
```

### Pre-requisites

- Running Kubernetes cluster with network policy support
- `kubectl` configured and connected
- CNI plugin that supports network policies (Calico, Cilium, etc.)
- Sufficient cluster resources for test pods

## Test Structure

```
integration-tests/
├── scenarios/           # Test scenario implementations
│   ├── multi-policy-combination.sh
│   ├── three-tier-application.sh
│   ├── cross-namespace.sh
│   ├── microservices-mesh.sh
│   ├── policy-conflicts.sh
│   ├── performance-load.sh
│   └── failure-recovery.sh
├── fixtures/           # Test data and manifests (future)
├── helpers/            # Common helper functions
│   └── common.sh
└── README.md          # This file
```

## How Tests Work

Each integration test:

1. **Creates isolated namespace** with unique ID
2. **Deploys test pods** with specific labels
3. **Applies network policies** being tested
4. **Validates behavior** using wget/curl connectivity tests
5. **Cleans up** by deleting the namespace

### Example Test Flow

```bash
test_three_tier_application() {
    ns="integration-three-tier-$$"  # Unique namespace
    kubectl create namespace "$ns"

    # Deploy pods
    kubectl run frontend -n "$ns" --labels="tier=frontend"
    kubectl run backend -n "$ns" --labels="tier=backend"
    kubectl run database -n "$ns" --labels="tier=database"

    # Apply policies
    kubectl apply -n "$ns" -f three-tier-policies.yaml

    # Test connectivity
    # frontend → backend (should work)
    # backend → database (should work)
    # frontend → database (should be blocked)

    # Cleanup
    kubectl delete namespace "$ns"
}
```

## Test Output

Tests produce colored output:

- **PASS** (green): Test passed successfully
- **FAIL** (red): Test failed with error details
- **SKIP** (yellow): Test skipped (pods failed to start, etc.)
- **INFO** (cyan): Additional information (timing, metrics)

### Example Output

```
=== Multi-Policy Combinations ===
  [TEST] Multi-policy: deny-all + selective allow
    PASS: Multi-policy combination working correctly
  [TEST] Multi-policy: multiple ingress rules
    PASS: Multiple ingress rules working correctly

=== Integration Test Summary ===
Total Tests:  25
Passed:       25
Failed:       0

SUCCESS: All integration tests passed!
```

## Performance Tests

Performance tests measure:

- **Policy application time**: How long to apply 50 policies
- **Update latency**: Time for policy changes to propagate
- **Complex selectors**: Impact of multi-label matching
- **Scale**: Behavior with 20+ pods in namespace

Results are logged in test output:

```
[TEST] Performance: 50 policies application time
  INFO: Applied 50 policies in 12s
  PASS: 50 policies applied successfully in 12s
```

## Troubleshooting

### Tests Failing Due to Timeout

Increase pod ready timeout in test functions:
```bash
kubectl wait --for=condition=Ready pod/app -n "$ns" --timeout=120s
```

### Namespace Cleanup Issues

Manually clean up test namespaces:
```bash
kubectl get namespaces | grep integration- | awk '{print $1}' | xargs kubectl delete namespace --wait=false
```

### CNI Plugin Not Supporting Network Policies

Verify your CNI supports network policies:
```bash
# Check for Calico
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check for Cilium
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Connectivity Tests Failing

Tests use `wget` inside nginx containers. If nginx image changes, update tests to use appropriate tools.

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run Integration Tests
  run: |
    cd test-framework
    ./run-integration-tests.sh
```

### Expected Runtime

- **Full suite**: ~5-10 minutes (25 tests)
- **Individual scenario**: ~20-60 seconds
- Varies by cluster performance and CNI

## Adding New Tests

1. Create test function in appropriate scenario file:

```bash
test_my_new_scenario() {
    local ns="integration-mytest-$$"
    echo "  [TEST] My new test scenario"

    # Setup
    kubectl create namespace "$ns"
    # ... deploy pods, apply policies ...

    # Test
    if <condition>; then
        echo "    PASS: Test passed"
        kubectl delete namespace "$ns" --wait=false
        return 0
    else
        echo "    FAIL: Test failed"
        kubectl delete namespace "$ns" --wait=false
        return 1
    fi
}
```

2. Add test to runner in `run-integration-tests.sh`:

```bash
run_test test_my_new_scenario
```

3. Update test count in summary

## Related Documentation

- [BATS Unit Tests](../bats-tests/README.md) - 100% unit test coverage
- [Performance Benchmarks](../PERFORMANCE.md) - Performance testing framework
- [Coverage Report](../COVERAGE.md) - Overall test coverage

## License

Same as parent project.
