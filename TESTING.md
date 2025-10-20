# Testing Guide for Kubernetes Network Policy Recipes

Comprehensive guide to testing infrastructure, local development, CI/CD integration, and troubleshooting.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Test Infrastructure](#test-infrastructure)
  - [BATS Unit Tests](#bats-unit-tests)
  - [Integration Tests](#integration-tests)
  - [Coverage System](#coverage-system)
- [Local Development](#local-development)
  - [Prerequisites](#prerequisites)
  - [Running Tests Locally](#running-tests-locally)
  - [Writing New Tests](#writing-new-tests)
- [Pre-commit Hooks](#pre-commit-hooks)
- [CI/CD Integration](#cicd-integration)
- [Test Coverage](#test-coverage)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

This project has comprehensive automated testing covering:

- **115+ BATS unit tests** - Testing individual NetworkPolicy recipes
- **25 integration tests** - Testing complex multi-policy scenarios
- **100% recipe coverage** - Every recipe has corresponding tests
- **95%+ coverage threshold** - Enforced in CI/CD pipelines
- **5 CI/CD platforms** - GitHub Actions, GitLab CI, Jenkins, CircleCI, Azure Pipelines
- **Pre-commit hooks** - Automated quality checks before every commit

### Test Types

| Test Type | Count | Purpose | Runtime |
|-----------|-------|---------|---------|
| BATS Unit Tests | 115+ | Recipe validation, YAML syntax, basic functionality | ~5 min |
| Integration Tests | 25 | Multi-policy combinations, real-world scenarios | ~10 min |
| Performance Tests | 4 | Policy enforcement latency, scale testing | ~15 min |
| Pre-commit Hooks | 10+ | Code quality, security, formatting | ~30 sec |

## Quick Start

### Run All Tests

```bash
# Clone repository
git clone https://github.com/ahmetb/kubernetes-networkpolicy-tutorial.git
cd kubernetes-networkpolicy-tutorial

# Install dependencies
pip install pre-commit
sudo apt-get install parallel jq bats  # Ubuntu/Debian
# OR
brew install parallel jq bats-core  # macOS

# Setup pre-commit hooks
pre-commit install

# Create test cluster (if needed)
kind create cluster --name np-test

# Run all BATS tests
cd test-framework
./run-all-bats-tests.sh

# Run integration tests
./run-integration-tests.sh

# Generate coverage report
./lib/coverage-tracker.sh report
./lib/coverage-tracker.sh html
open results/coverage-report.html
```

### Run Specific Tests

```bash
# Run single BATS test file
bats test-framework/bats-tests/recipes/01-deny-all-traffic.bats

# Run specific integration test category
cd test-framework
source integration-tests/scenarios/multi-policy-combination.sh
test_deny_all_plus_selective_allow

# Run tests for specific recipes
./run-all-bats-tests.sh --filter "01,02,03"
```

## Test Infrastructure

### BATS Unit Tests

**Location**: `test-framework/bats-tests/`

BATS (Bash Automated Testing System) provides unit-level testing for each NetworkPolicy recipe.

#### Structure

```
test-framework/bats-tests/
├── recipes/              # Test files for each recipe
│   ├── 00-create-cluster.bats
│   ├── 01-deny-all-traffic.bats
│   ├── 02-limit-traffic.bats
│   └── ... (15 total)
├── helpers/             # Shared test utilities
│   └── test_helper.bash
└── fixtures/           # Test data and manifests
```

#### What BATS Tests Cover

Each recipe has 5-8 test cases covering:

1. **YAML Validation** - Syntax correctness
2. **Policy Application** - Can be applied without errors
3. **Traffic Blocking** - Denied traffic is actually blocked
4. **Traffic Allowing** - Allowed traffic flows correctly
5. **Label Matching** - Selectors match correct pods
6. **Edge Cases** - Empty selectors, namespace boundaries, etc.
7. **Policy Retrieval** - Can be queried via kubectl
8. **Egress/Ingress Isolation** - Policy types work correctly

#### Running BATS Tests

```bash
# Run all BATS tests
cd test-framework
./run-all-bats-tests.sh

# Run with verbose output
./run-all-bats-tests.sh --verbose

# Run specific test file
bats bats-tests/recipes/01-deny-all-traffic.bats

# Run specific test within a file
bats bats-tests/recipes/01-deny-all-traffic.bats --filter "deny all ingress"

# Generate TAP output
./run-all-bats-tests.sh --tap > results.tap

# Generate JUnit XML
./run-all-bats-tests.sh --junit > results.xml
```

#### BATS Test Example

```bash
#!/usr/bin/env bats
# Test Recipe 01: Deny All Traffic

load '../helpers/test_helper'

setup() {
    TEST_NS="test-01-$(date +%s)"
    create_test_namespace
}

@test "01: Policy should deny all ingress traffic" {
    # Create pods
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Traffic works before policy
    test_connectivity "client" "web" "allow"

    # Apply policy
    kubectl apply -n "${TEST_NS}" -f policy.yaml
    wait_for_policy_enforcement

    # Traffic should be blocked
    test_connectivity "client" "web" "deny"
}

teardown() {
    kubectl delete namespace "${TEST_NS}" --wait=false
}
```

### Integration Tests

**Location**: `test-framework/integration-tests/`

Integration tests validate complex, real-world scenarios involving multiple policies and components.

#### Test Categories

1. **Multi-Policy Combinations** (3 tests)
   - Deny-all + selective allow
   - Multiple ingress rules on same pod
   - Policy precedence and order independence

2. **Three-Tier Applications** (3 tests)
   - Frontend → Backend → Database isolation
   - Monitoring sidecar patterns
   - Port-specific restrictions

3. **Cross-Namespace Communication** (3 tests)
   - Namespace selector policies
   - Complete namespace isolation
   - Selective cross-namespace access

4. **Microservices Patterns** (3 tests)
   - Service mesh communication
   - Sidecar proxy patterns
   - Canary deployment routing

5. **Policy Conflicts** (4 tests)
   - Overlapping selectors (union behavior)
   - Ingress vs egress conflicts
   - Empty selector matching

6. **Performance & Scale** (4 tests)
   - 50+ policies application time
   - Complex selector matching
   - Policy update propagation latency

7. **Failure Recovery** (5 tests)
   - Pod restart policy persistence
   - Invalid policy rejection
   - Namespace deletion cleanup

#### Running Integration Tests

```bash
cd test-framework
./run-integration-tests.sh

# Run with verbose output
./run-integration-tests.sh --verbose

# Run specific scenario
source integration-tests/scenarios/multi-policy-combination.sh
test_deny_all_plus_selective_allow

# Validate integration test setup
./validate-integration-tests.sh
```

#### Integration Test Output

```
=== Multi-Policy Combinations ===
  [TEST] Multi-policy: deny-all + selective allow
    PASS: Multi-policy combination working correctly (8s)
  [TEST] Multiple ingress rules on same pod
    PASS: Multiple rules evaluated correctly (6s)

=== Three-Tier Applications ===
  [TEST] Frontend → Backend → Database isolation
    PASS: Three-tier isolation working (12s)

=== Test Summary ===
Total Tests:  25
Passed:       25
Failed:       0
Runtime:      187s

SUCCESS: All integration tests passed!
```

### Coverage System

**Documentation**: `test-framework/COVERAGE.md`

The coverage system tracks test coverage across all recipes and enforces thresholds.

#### Coverage Metrics

| Metric | Current | Threshold | Status |
|--------|---------|-----------|--------|
| Overall Coverage | 100% | 95% | ✅ PASS |
| BATS Unit Tests | 100% | 95% | ✅ PASS |
| Integration Tests | 100% | 90% | ✅ PASS |
| Recipe Coverage | 100% | 100% | ✅ PASS |

#### Generate Coverage Reports

```bash
cd test-framework

# Generate JSON report
./lib/coverage-tracker.sh report

# Generate HTML report
./lib/coverage-tracker.sh html
open results/coverage-report.html  # macOS
xdg-open results/coverage-report.html  # Linux

# Get specific metrics
./lib/coverage-tracker.sh bats           # BATS coverage %
./lib/coverage-tracker.sh integration   # Integration coverage %
./lib/coverage-tracker.sh recipe        # Recipe coverage %

# Generate badges
./lib/badge-generator.sh all

# Check coverage threshold
./lib/coverage-enforcer.sh all
```

## Local Development

### Prerequisites

#### Required Tools

- **kubectl** - Kubernetes CLI (v1.27+)
- **jq** - JSON processor
- **parallel** - GNU Parallel
- **bats** - Bash Automated Testing System
- **pre-commit** - Git pre-commit hook framework
- **Python 3.8+** - For pre-commit hooks

#### Install on Ubuntu/Debian

```bash
# Update package list
sudo apt-get update

# Install core tools
sudo apt-get install -y kubectl jq parallel bats python3-pip

# Install pre-commit
pip3 install pre-commit

# Verify installations
kubectl version --client
jq --version
parallel --version
bats --version
pre-commit --version
```

#### Install on macOS

```bash
# Using Homebrew
brew install kubectl jq parallel bats-core pre-commit

# Verify installations
kubectl version --client
jq --version
parallel --version
bats --version
pre-commit --version
```

#### Kubernetes Cluster

You need a Kubernetes cluster with NetworkPolicy support. Options:

**kind (recommended for local testing)**:
```bash
# Install kind
brew install kind  # macOS
# OR
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create cluster with Calico
./00-create-cluster.md
# OR manually:
kind create cluster --name np-test --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: 192.168.0.0/16
EOF

# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

**minikube**:
```bash
minikube start --cni=calico --network-plugin=cni
```

**GKE (Google Kubernetes Engine)**:
```bash
gcloud container clusters create np-test \
    --enable-network-policy \
    --zone us-central1-b
```

#### Verify NetworkPolicy Support

```bash
# Check API version
kubectl api-versions | grep networking.k8s.io/v1

# Check CNI plugin
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# Verify NetworkPolicy resources are available
kubectl api-resources | grep networkpolicies
```

### Running Tests Locally

#### BATS Tests

```bash
cd test-framework

# Run all BATS tests
./run-all-bats-tests.sh

# Run with options
./run-all-bats-tests.sh --verbose    # Detailed output
./run-all-bats-tests.sh --timing     # Show test durations
./run-all-bats-tests.sh --tap        # TAP format output
./run-all-bats-tests.sh --junit      # JUnit XML output

# Run specific recipes
./run-all-bats-tests.sh --filter "01,02,09"

# Run single test file
bats bats-tests/recipes/01-deny-all-traffic.bats

# Run with specific test filter
bats bats-tests/recipes/01-deny-all-traffic.bats --filter "deny all ingress"
```

#### Integration Tests

```bash
cd test-framework

# Run all integration tests
./run-integration-tests.sh

# Run with verbose output
./run-integration-tests.sh --verbose

# Validate test framework
./validate-integration-tests.sh

# Run specific scenario
source integration-tests/scenarios/multi-policy-combination.sh
test_deny_all_plus_selective_allow

# Run all tests in a scenario file
source integration-tests/scenarios/three-tier-application.sh
test_three_tier_isolation
test_three_tier_with_monitoring
test_three_tier_port_restrictions
```

#### Performance Tests

```bash
cd test-framework

# Run performance benchmark on a recipe
./performance-benchmark.sh --recipe ../01-deny-all-traffic-to-an-application.md

# Create baseline
./performance-benchmark.sh \
  --recipe ../01-deny-all-traffic-to-an-application.md \
  --baseline

# Compare against baseline
./performance-benchmark.sh \
  --recipe ../01-deny-all-traffic-to-an-application.md \
  --compare ./benchmark-results/baseline.json \
  --threshold 10

# Generate analysis report
./analyze-performance.sh --format html --recommendations
```

#### Coverage Reports

```bash
cd test-framework

# Generate reports
./lib/coverage-tracker.sh report
./lib/coverage-tracker.sh html

# View HTML report
open results/coverage-report.html

# Generate badges
./lib/badge-generator.sh all

# Check thresholds
./lib/coverage-enforcer.sh all
```

### Writing New Tests

#### Adding a BATS Test

**1. Create test file:**

```bash
touch test-framework/bats-tests/recipes/15-new-recipe.bats
chmod +x test-framework/bats-tests/recipes/15-new-recipe.bats
```

**2. Write test using template:**

```bash
#!/usr/bin/env bats
# BATS tests for Recipe 15: Your Recipe Title
# Description of what this recipe tests

load '../helpers/test_helper'

setup() {
    # Generate unique namespace for this test run
    TEST_NS="${TEST_NAMESPACE_PREFIX}-15-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"

    create_test_namespace
}

@test "15: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/15-new-recipe.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "15: Your test description" {
    # Create test pods
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Test initial state
    test_connectivity "client" "web" "allow"

    # Apply NetworkPolicy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-policy
spec:
  podSelector:
    matchLabels:
      app: web
  # ... policy spec ...
EOF

    # Wait for policy enforcement
    wait_for_policy_enforcement

    # Test expected behavior
    test_connectivity "client" "web" "deny"
}

teardown() {
    # Cleanup happens automatically via helper
    cleanup_test_namespace
}
```

**3. Use helper functions:**

Available helpers from `test_helper.bash`:

- `create_test_namespace` - Creates isolated test namespace
- `create_test_pod <name> <labels>` - Creates nginx pod with labels
- `test_connectivity <from> <to> <expect>` - Tests pod-to-pod connectivity
- `wait_for_policy_enforcement` - Waits for CNI to enforce policies
- `verify_network_policy <name>` - Checks policy exists
- `extract_yaml_from_recipe <file>` - Extracts YAML from markdown
- `validate_yaml <file>` - Validates YAML syntax
- `cleanup_test_namespace` - Deletes test namespace

**4. Test locally:**

```bash
# Run your new test
bats test-framework/bats-tests/recipes/15-new-recipe.bats

# Run with verbose output
bats test-framework/bats-tests/recipes/15-new-recipe.bats --verbose
```

#### Adding an Integration Test

**1. Choose or create scenario file:**

```bash
# Edit existing scenario
vim test-framework/integration-tests/scenarios/multi-policy-combination.sh

# Or create new scenario
touch test-framework/integration-tests/scenarios/new-scenario.sh
chmod +x test-framework/integration-tests/scenarios/new-scenario.sh
```

**2. Write test function:**

```bash
#!/bin/bash
# Integration tests for [scenario category]

test_your_scenario() {
    local ns="integration-yourtest-$$"
    echo "  [TEST] Your test description"

    # Setup
    kubectl create namespace "$ns" || return 1
    kubectl label namespace "$ns" test=integration

    # Deploy pods
    kubectl run app1 -n "$ns" --image=nginx --labels="app=web" --wait || {
        echo "    FAIL: Failed to create app1"
        kubectl delete namespace "$ns" --wait=false
        return 1
    }

    kubectl run app2 -n "$ns" --image=nginx --labels="app=api" --wait || {
        echo "    FAIL: Failed to create app2"
        kubectl delete namespace "$ns" --wait=false
        return 1
    }

    # Wait for pods
    kubectl wait --for=condition=Ready pod/app1 -n "$ns" --timeout=60s || {
        echo "    FAIL: app1 not ready"
        kubectl delete namespace "$ns" --wait=false
        return 1
    }

    # Apply policies
    kubectl apply -n "$ns" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-policy
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress: []
EOF

    # Wait for enforcement
    sleep 10

    # Test connectivity
    if kubectl exec -n "$ns" app2 -- wget -qO- --timeout=2 http://app1 &>/dev/null; then
        echo "    FAIL: Traffic should be blocked but succeeded"
        kubectl delete namespace "$ns" --wait=false
        return 1
    fi

    # Success
    echo "    PASS: Scenario validated correctly"
    kubectl delete namespace "$ns" --wait=false
    return 0
}
```

**3. Add to test runner:**

Edit `test-framework/run-integration-tests.sh`:

```bash
# Source your scenario file
source "${SCRIPT_DIR}/integration-tests/scenarios/new-scenario.sh"

# Add test to execution
run_test test_your_scenario
```

**4. Test locally:**

```bash
cd test-framework
./run-integration-tests.sh
```

## Pre-commit Hooks

**Documentation**: `docs/PRE_COMMIT.md`

Pre-commit hooks run automatically before every commit to ensure code quality.

### Installation

```bash
# Install pre-commit
pip install pre-commit

# Install hooks in repository
cd kubernetes-network-policy-recipes
pre-commit install

# Verify installation
pre-commit --version
```

### What Hooks Check

- **YAML syntax** - All YAML files are valid
- **Shell scripts** - Shellcheck linting
- **Markdown formatting** - Consistent style
- **Security** - Secret detection (detect-secrets)
- **File checks** - Trailing whitespace, file size limits
- **BATS tests** - Recipe files have corresponding tests
- **Kubernetes API** - Deprecated API versions

### Running Hooks

```bash
# Automatic on commit
git add .
git commit -m "Your message"
# Hooks run automatically

# Manual on all files
pre-commit run --all-files

# Manual on specific files
pre-commit run --files path/to/file.yaml

# Manual for specific hook
pre-commit run shellcheck --all-files
pre-commit run yamllint --all-files

# Update hook versions
pre-commit autoupdate
```

### Common Hook Failures

**YAML linting failed:**
```bash
# Check what's wrong
yamllint path/to/file.yaml

# Auto-fix is not available, edit manually based on output
```

**Shell script linting failed:**
```bash
# Check issues
shellcheck path/to/script.sh

# Common fixes:
# - Quote variables: "$VAR" instead of $VAR
# - Use [[ ]] instead of [ ]
# - Add 'local' to function variables
```

**BATS test missing:**
```bash
# If you added 15-new-recipe.md, create:
touch test-framework/bats-tests/recipes/15-new-recipe.bats

# Use existing test as template
cp test-framework/bats-tests/recipes/01-deny-all-traffic.bats \
   test-framework/bats-tests/recipes/15-new-recipe.bats
```

**Secret detected:**
```bash
# Update baseline if false positive
detect-secrets scan --baseline .secrets.baseline

# Audit baseline
detect-secrets audit .secrets.baseline
```

## CI/CD Integration

**Full Documentation**: `test-framework/CICD.md`

Tests run automatically in 5 CI/CD platforms:

### Supported Platforms

1. **GitHub Actions** - `.github/workflows/test.yml`
2. **GitLab CI** - `.gitlab-ci.yml`
3. **Jenkins** - `Jenkinsfile`
4. **CircleCI** - `.circleci/config.yml`
5. **Azure Pipelines** - `azure-pipelines.yml`

### GitHub Actions (Primary)

**Workflow**: `.github/workflows/test.yml`

**Features**:
- Runs on push, PR, and daily schedule
- Matrix testing: Multiple K8s versions × CNI plugins
- Automated PR comments with test results
- Coverage badge generation
- HTML report artifacts

**Triggers**:
```yaml
on:
  push:
    branches: [master, main]
  pull_request:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:
```

**Jobs**:
1. **pre-commit** - Run pre-commit hooks
2. **bats-tests** - Run all BATS unit tests
3. **test-kind** - Integration tests on kind cluster
4. **coverage-report** - Generate and enforce coverage
5. **pr-comment** - Add test results to PR

**Viewing Results**:
```bash
# Go to GitHub repository
# Actions tab → Select workflow run
# Download artifacts for HTML reports
```

### GitLab CI

**Config**: `.gitlab-ci.yml`

**Stages**: setup → test → report → cleanup

**Jobs**:
- `test:kind:calico` - kind with Calico CNI
- `test:kind:cilium` - kind with Cilium CNI
- `test:gke:calico` - GKE with Calico (scheduled only)
- `coverage-report` - Generate coverage
- `pages` - Publish to GitLab Pages

### Jenkins

**Pipeline**: `Jenkinsfile`

**Parameters**:
- Provider: kind, minikube, gke, eks, aks
- CNI: calico, cilium, weave
- Skip Unsupported: true/false

**Artifacts**:
- Test results (JSON)
- HTML reports
- JUnit XML

### CircleCI

**Config**: `.circleci/config.yml`

**Workflows**:
- `test` - On push/PR
- `nightly` - Scheduled daily

**Features**:
- Parallel test execution
- Kubernetes orb integration
- Slack notifications

### Azure Pipelines

**Config**: `azure-pipelines.yml`

**Stages**:
- Test - Run all tests
- Report - Generate reports and badges

**Features**:
- Matrix strategy for K8s versions
- Native test reporting
- 30-day artifact retention

### CI/CD Best Practices

1. **Use kind for fast feedback** - Run on every PR
2. **Cloud testing for scheduled runs** - GKE/EKS/AKS cost money
3. **Always use --skip-unsupported** - Prevent false failures
4. **Cache dependencies** - Speed up pipeline
5. **Enforce coverage thresholds** - Maintain quality
6. **Generate artifacts** - Keep test history

## Test Coverage

**Full Documentation**: `test-framework/COVERAGE.md`

### Current Coverage

```
Overall Coverage:    100%  ✅
BATS Unit Tests:     100%  ✅
Integration Tests:   100%  ✅
Recipe Coverage:     100%  ✅
Total Test Cases:    115+
```

### Coverage Thresholds

| Metric | Minimum | Target | Enforcement |
|--------|---------|--------|-------------|
| Overall | 95% | 100% | CI fails if < 95% |
| BATS | 95% | 100% | Warning if < 95% |
| Integration | 90% | 100% | Warning if < 90% |
| Recipe | 100% | 100% | CI fails if < 100% |

### Coverage Badges

Badges are automatically generated and stored in `badges/`:

```markdown
![Test Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/USER/REPO/badges/coverage.json)
![BATS Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/USER/REPO/badges/bats-coverage.json)
![Tests](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/USER/REPO/badges/tests.json)
```

### Maintaining Coverage

When adding new recipes:

1. **Create recipe file**: `15-new-recipe.md`
2. **Create BATS test**: `test-framework/bats-tests/recipes/15-new-recipe.bats`
3. **Add integration test** (if needed): Add to existing scenario or create new
4. **Run coverage check**: `./lib/coverage-tracker.sh report`
5. **Verify thresholds**: `./lib/coverage-enforcer.sh all`

## Troubleshooting

### Common Issues

#### Tests Failing in CI but Pass Locally

**Symptoms**: Tests pass on your machine, fail in CI/CD

**Causes**:
- CI has slower resources
- Timing issues with policy enforcement
- CNI plugin differences

**Solutions**:

```bash
# 1. Increase timeout in test
export TEST_TIMEOUT=120  # Default is 60

# 2. Increase policy enforcement wait time
# In test file, increase sleep duration:
sleep 15  # Instead of sleep 5

# 3. Reduce parallel workers in CI
export MAX_WORKERS=2  # Default is 4

# 4. Check CNI support
./test-framework/parallel-test-runner.sh --detect
./test-framework/parallel-test-runner.sh --skip-unsupported
```

#### Pods Not Starting

**Symptoms**: Pods stuck in Pending or ImagePullBackoff

**Solutions**:

```bash
# Check pod status
kubectl get pods -n <test-namespace>
kubectl describe pod <pod-name> -n <test-namespace>

# Check cluster resources
kubectl top nodes
kubectl describe nodes

# Check image pull status
kubectl get events -n <test-namespace>

# Increase pod ready timeout in tests
kubectl wait --for=condition=Ready pod/<pod> -n <ns> --timeout=120s
```

#### NetworkPolicy Not Enforcing

**Symptoms**: Traffic flows when it should be blocked

**Causes**:
- CNI doesn't support NetworkPolicy
- Policy not applied correctly
- Enforcement delay

**Solutions**:

```bash
# 1. Verify CNI supports NetworkPolicy
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# 2. Check if policy exists
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <policy-name> -n <namespace>

# 3. Increase enforcement wait time
# In test, add longer sleep after applying policy
sleep 15  # Allow CNI time to enforce

# 4. Check CNI logs
kubectl logs -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l k8s-app=cilium

# 5. Verify pod labels match policy selectors
kubectl get pods --show-labels -n <namespace>
```

#### Coverage Threshold Failing

**Symptoms**: CI fails with "Coverage below threshold"

**Solutions**:

```bash
# Check current coverage
cd test-framework
./lib/coverage-tracker.sh report
cat results/coverage-report.json

# Identify missing tests
./lib/coverage-enforcer.sh all

# Create missing BATS tests
# For each recipe without test:
touch bats-tests/recipes/XX-recipe-name.bats

# Verify coverage improved
./lib/coverage-tracker.sh report
```

#### Pre-commit Hooks Failing

**Symptoms**: `git commit` fails with hook errors

**Common Issues**:

**YAML syntax error:**
```bash
# Run yamllint manually
yamllint path/to/file.yaml

# Fix issues (no auto-fix available)
# Common: indentation, line length, trailing spaces
```

**Shellcheck error:**
```bash
# Run shellcheck manually
shellcheck path/to/script.sh

# Common fixes:
# Quote variables: "$VAR" not $VAR
# Use [[ ]] for tests
# Declare 'local' in functions
```

**Missing BATS test:**
```bash
# Create test file for new recipe
touch test-framework/bats-tests/recipes/15-new-recipe.bats
```

**Secret detected:**
```bash
# Review detection
detect-secrets audit .secrets.baseline

# Update baseline if false positive
detect-secrets scan --baseline .secrets.baseline
```

#### Namespace Cleanup Issues

**Symptoms**: Old test namespaces not deleted

**Solutions**:

```bash
# List test namespaces
kubectl get namespaces | grep 'np-test-\|integration-'

# Delete all test namespaces
kubectl get namespaces -o name | grep 'np-test-\|integration-' | xargs kubectl delete --wait=false

# Automated cleanup
cd test-framework
./cleanup-environment.sh --all-test-ns --age 1h

# Force delete stuck namespaces
kubectl delete namespace <namespace> --grace-period=0 --force
```

#### BATS Not Found

**Symptoms**: `bats: command not found`

**Solutions**:

```bash
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local

# Verify installation
bats --version
```

#### GNU Parallel Not Found

**Symptoms**: `parallel: command not found`

**Solutions**:

```bash
# Ubuntu/Debian
sudo apt-get install parallel

# macOS
brew install parallel

# Verify installation
parallel --version
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
# BATS tests with verbose output
bats test-framework/bats-tests/recipes/01-deny-all-traffic.bats --verbose

# Integration tests with debug
cd test-framework
bash -x ./run-integration-tests.sh

# Parallel test runner with verbose
cd test-framework
./run-all-bats-tests.sh --verbose --timing

# Keep test namespaces for inspection
# Comment out cleanup in test files
# teardown() {
#     # kubectl delete namespace "${TEST_NS}"
# }
```

### Getting Help

1. **Check documentation**:
   - This file: `TESTING.md`
   - CI/CD guide: `test-framework/CICD.md`
   - Coverage: `test-framework/COVERAGE.md`
   - Pre-commit: `docs/PRE_COMMIT.md`

2. **Review test logs**:
   - CI/CD: Check pipeline logs
   - Local: Run with `--verbose` flag

3. **Check cluster state**:
   ```bash
   kubectl cluster-info
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

4. **Open an issue**:
   - GitHub: https://github.com/ahmetb/kubernetes-networkpolicy-tutorial/issues
   - Include: Error message, test output, cluster info

## Best Practices

### Writing Tests

1. **Use descriptive test names**
   ```bash
   # Good
   @test "01: Policy should deny all ingress traffic to target pod"

   # Bad
   @test "test 1"
   ```

2. **Test one thing per test**
   - Each `@test` should verify a single behavior
   - Makes failures easier to diagnose

3. **Use helper functions**
   - Leverage `test_helper.bash` functions
   - Don't duplicate setup logic

4. **Clean up properly**
   - Always delete test namespaces in `teardown()`
   - Use `--wait=false` for faster cleanup

5. **Handle timing**
   - Wait for pods to be ready: `kubectl wait`
   - Wait for policy enforcement: `wait_for_policy_enforcement`
   - Increase timeouts in slow environments

6. **Add comments**
   - Explain what you're testing and why
   - Document any non-obvious logic

### Running Tests

1. **Run locally before pushing**
   ```bash
   # Run pre-commit hooks
   pre-commit run --all-files

   # Run BATS tests
   cd test-framework && ./run-all-bats-tests.sh

   # Run integration tests
   ./run-integration-tests.sh
   ```

2. **Use appropriate environments**
   - **kind** - Fast local testing
   - **minikube** - Local testing with different drivers
   - **GKE/EKS/AKS** - Cloud testing (scheduled only, costs money)

3. **Monitor resource usage**
   ```bash
   kubectl top nodes
   kubectl top pods --all-namespaces
   ```

4. **Check coverage regularly**
   ```bash
   cd test-framework
   ./lib/coverage-tracker.sh report
   ./lib/coverage-enforcer.sh all
   ```

### Debugging Tests

1. **Keep namespaces for inspection**
   - Comment out cleanup in `teardown()`
   - Inspect resources: `kubectl get all -n <namespace>`

2. **Use kubectl debug**
   ```bash
   kubectl debug pod/<pod> -n <namespace> --image=nicolaka/netshoot
   ```

3. **Check connectivity manually**
   ```bash
   kubectl exec -it pod/client -n <namespace> -- wget -qO- http://target
   ```

4. **Review policy details**
   ```bash
   kubectl get networkpolicy -n <namespace>
   kubectl describe networkpolicy <name> -n <namespace>
   ```

### Contributing Tests

1. **Follow existing patterns**
   - Look at similar tests for structure
   - Use consistent naming conventions

2. **Test edge cases**
   - Empty selectors
   - Missing labels
   - Cross-namespace scenarios

3. **Update documentation**
   - Add test to this guide if it's a new category
   - Update coverage docs

4. **Verify CI passes**
   - Check GitHub Actions after pushing
   - Fix any failures before requesting review

## Additional Resources

### Documentation

- [Main README](README.md) - Project overview
- [Contributing Guide](CONTRIBUTING.md) - Contribution process
- [CI/CD Guide](test-framework/CICD.md) - Platform-specific CI/CD
- [Coverage Documentation](test-framework/COVERAGE.md) - Coverage system
- [Pre-commit Guide](docs/PRE_COMMIT.md) - Pre-commit hooks
- [Performance Guide](test-framework/PERFORMANCE.md) - Performance testing

### External Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [kind Documentation](https://kind.sigs.k8s.io/)
- [Calico NetworkPolicy](https://docs.tigera.io/calico/latest/network-policy/)
- [Pre-commit Documentation](https://pre-commit.com/)

### Videos & Talks

- [KubeCon Talk: Securing Kubernetes Network](https://www.youtube.com/watch?v=3gGpMmYeEO8)
- [Kubernetes NetworkPolicy Tutorial](https://ahmet.im/blog/kubernetes-network-policy/)

---

**Last Updated**: 2025-10-17
**Maintained By**: Kubernetes Network Policy Recipes Contributors

For questions or issues, please open an issue on [GitHub](https://github.com/ahmetb/kubernetes-networkpolicy-tutorial/issues).
