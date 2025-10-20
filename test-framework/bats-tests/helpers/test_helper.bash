#!/usr/bin/env bash
# BATS Test Helper Functions for NetworkPolicy Recipes
# This file provides common helper functions for all BATS tests

# Load BATS libraries
load '../../bats-libs/bats-support/load'
load '../../bats-libs/bats-assert/load'
load '../../bats-libs/bats-file/load'

# Load existing test functions
source "${BATS_TEST_DIRNAME}/../../lib/test-functions.sh"
source "${BATS_TEST_DIRNAME}/../../lib/ci-helpers.sh"

# Global test configuration
export BATS_TEST_TIMEOUT=60
export TEST_NAMESPACE_PREFIX="bats-test"

# Setup function called before each test
setup() {
    # Generate unique test namespace
    export TEST_NS="${TEST_NAMESPACE_PREFIX}-$(date +%s)-$$"
    export TEST_START_TIME=$(date +%s)

    # Set test context
    export RECIPE_DIR="${BATS_TEST_DIRNAME}/../.."
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
}

# Teardown function called after each test
teardown() {
    # Calculate test duration
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    echo "# Test duration: ${duration}s" >&3

    # Cleanup test namespace if it exists
    if kubectl get namespace "${TEST_NS}" &>/dev/null; then
        echo "# Cleaning up namespace: ${TEST_NS}" >&3
        kubectl delete namespace "${TEST_NS}" --wait=true --timeout=30s || true
    fi

    # Cleanup temp directory
    rm -rf "${TEST_TEMP_DIR}"
}

# Helper: Extract YAML from recipe markdown file
# Usage: extract_yaml_from_recipe "path/to/recipe.md"
extract_yaml_from_recipe() {
    local recipe_file="$1"
    local yaml_file="${TEST_TEMP_DIR}/policy.yaml"

    # Extract YAML content between ```yaml and ``` markers
    awk '/```yaml/,/```/' "${recipe_file}" | grep -v '```' > "${yaml_file}"

    echo "${yaml_file}"
}

# Helper: Validate YAML syntax
# Usage: validate_yaml "path/to/yaml/file"
validate_yaml() {
    local yaml_file="$1"

    # Check if file exists
    assert_file_exist "${yaml_file}"

    # Validate with kubectl --dry-run
    run kubectl apply --dry-run=client -f "${yaml_file}"
    assert_success
}

# Helper: Create test namespace
# Usage: create_test_namespace
create_test_namespace() {
    run kubectl create namespace "${TEST_NS}"
    assert_success

    # Label namespace for cleanup
    kubectl label namespace "${TEST_NS}" \
        test-runner=bats \
        test-timestamp="$(date +%s)" \
        --overwrite
}

# Helper: Apply NetworkPolicy from file
# Usage: apply_network_policy "path/to/policy.yaml"
apply_network_policy() {
    local policy_file="$1"

    run kubectl apply -f "${policy_file}" -n "${TEST_NS}"
    assert_success

    # Wait for policy to be created
    sleep 2
}

# Helper: Create test pod
# Usage: create_test_pod "pod-name" "label-key=label-value"
create_test_pod() {
    local pod_name="$1"
    local labels="${2:-app=${pod_name}}"

    cat <<EOF | kubectl apply -n "${TEST_NS}" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  labels:
    ${labels//=/:
    }
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
EOF

    # Wait for pod to be ready
    run kubectl wait --for=condition=Ready \
        pod/"${pod_name}" \
        -n "${TEST_NS}" \
        --timeout=60s
    assert_success
}

# Helper: Test network connectivity between pods
# Usage: test_connectivity "source-pod" "destination-pod" "expected-result"
# expected-result: "allow" or "deny"
test_connectivity() {
    local source_pod="$1"
    local dest_pod="$2"
    local expected="$3"

    # Get destination pod IP
    local dest_ip=$(kubectl get pod "${dest_pod}" -n "${TEST_NS}" \
        -o jsonpath='{.status.podIP}')

    # Test connectivity with timeout
    local result=0
    kubectl exec "${source_pod}" -n "${TEST_NS}" -- \
        wget -T 2 -O- "http://${dest_ip}:80" &>/dev/null || result=$?

    if [[ "${expected}" == "allow" ]]; then
        assert_equal "${result}" "0" "Connection should be allowed"
    elif [[ "${expected}" == "deny" ]]; then
        assert_not_equal "${result}" "0" "Connection should be denied"
    fi
}

# Helper: Test port connectivity
# Usage: test_port_connectivity "source-pod" "dest-ip" "port" "expected"
test_port_connectivity() {
    local source_pod="$1"
    local dest_ip="$2"
    local port="$3"
    local expected="$4"

    local result=0
    kubectl exec "${source_pod}" -n "${TEST_NS}" -- \
        nc -z -w 2 "${dest_ip}" "${port}" &>/dev/null || result=$?

    if [[ "${expected}" == "allow" ]]; then
        assert_equal "${result}" "0" "Port ${port} should be accessible"
    else
        assert_not_equal "${result}" "0" "Port ${port} should be blocked"
    fi
}

# Helper: Verify NetworkPolicy exists
# Usage: verify_network_policy "policy-name"
verify_network_policy() {
    local policy_name="$1"

    run kubectl get networkpolicy "${policy_name}" -n "${TEST_NS}"
    assert_success
}

# Helper: Get policy details
# Usage: get_policy_details "policy-name"
get_policy_details() {
    local policy_name="$1"

    kubectl get networkpolicy "${policy_name}" \
        -n "${TEST_NS}" \
        -o yaml
}

# Helper: Create multiple test pods
# Usage: create_multiple_pods "prefix" "count" "labels"
create_multiple_pods() {
    local prefix="$1"
    local count="$2"
    local labels="$3"

    for i in $(seq 1 "${count}"); do
        create_test_pod "${prefix}-${i}" "${labels}"
    done
}

# Helper: Test egress connectivity
# Usage: test_egress "pod-name" "external-host" "expected"
test_egress() {
    local pod_name="$1"
    local external_host="$2"
    local expected="$3"

    local result=0
    kubectl exec "${pod_name}" -n "${TEST_NS}" -- \
        wget -T 2 -O- "${external_host}" &>/dev/null || result=$?

    if [[ "${expected}" == "allow" ]]; then
        assert_equal "${result}" "0" "Egress to ${external_host} should be allowed"
    else
        assert_not_equal "${result}" "0" "Egress to ${external_host} should be denied"
    fi
}

# Helper: Create namespace with labels
# Usage: create_labeled_namespace "namespace-name" "key=value,key2=value2"
create_labeled_namespace() {
    local ns_name="$1"
    local labels="$2"

    kubectl create namespace "${ns_name}"

    # Apply labels
    IFS=',' read -ra LABEL_ARRAY <<< "${labels}"
    for label in "${LABEL_ARRAY[@]}"; do
        kubectl label namespace "${ns_name}" "${label}" --overwrite
    done
}

# Helper: Wait for NetworkPolicy to take effect
# Usage: wait_for_policy_enforcement
wait_for_policy_enforcement() {
    # NetworkPolicies typically take 2-5 seconds to enforce
    sleep 5
}

# Helper: Print test debug info
# Usage: debug_test_state
debug_test_state() {
    echo "# === Test Debug Information ===" >&3
    echo "# Namespace: ${TEST_NS}" >&3
    echo "# Pods:" >&3
    kubectl get pods -n "${TEST_NS}" -o wide >&3 2>&1 || true
    echo "# NetworkPolicies:" >&3
    kubectl get networkpolicies -n "${TEST_NS}" >&3 2>&1 || true
    echo "# Events:" >&3
    kubectl get events -n "${TEST_NS}" --sort-by='.lastTimestamp' >&3 2>&1 || true
}

# Helper: Cleanup all BATS test namespaces
# Usage: cleanup_all_bats_namespaces
cleanup_all_bats_namespaces() {
    kubectl get namespaces -l test-runner=bats -o name | \
        xargs -r kubectl delete --wait=false
}
