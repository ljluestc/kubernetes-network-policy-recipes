#!/usr/bin/env bats
# BATS tests for Recipe 05: Allow Traffic from All Namespaces
# Tests cross-namespace allow policy

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-05-$(date +%s)-$$"
    TEST_NS_OTHER="${TEST_NS}-other"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

teardown() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    echo "# Test duration: ${duration}s" >&3

    kubectl delete namespace "${TEST_NS}" --wait=true --timeout=30s 2>/dev/null || true
    kubectl delete namespace "${TEST_NS_OTHER}" --wait=true --timeout=30s 2>/dev/null || true

    rm -rf "${TEST_TEMP_DIR}"
}

@test "05: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/05-allow-traffic-from-all-namespaces.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "05: Policy should allow traffic from all namespaces" {
    # Create web pod in primary namespace
    create_test_pod "web" "app=web"

    # Create client in same namespace
    create_test_pod "internal-client" "app=client"

    # Create external namespace and client
    kubectl create namespace "${TEST_NS_OTHER}"
    kubectl run external-client --image=nginx:alpine -n "${TEST_NS_OTHER}"
    kubectl wait --for=condition=Ready pod/external-client -n "${TEST_NS_OTHER}" --timeout=60s

    # First apply default-deny
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    # Apply policy allowing from all namespaces
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all-namespaces
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Internal traffic should work
    test_connectivity "internal-client" "web" "allow"

    # External traffic should also work
    local result=0
    kubectl exec external-client -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result=$?

    assert_equal "${result}" "0" "Cross-namespace traffic should be allowed"
}

@test "05: Empty namespaceSelector matches all namespaces" {
    create_test_pod "web" "app=web"

    # Create multiple external namespaces
    local ns2="${TEST_NS}-ns2"
    local ns3="${TEST_NS}-ns3"

    kubectl create namespace "${ns2}"
    kubectl create namespace "${ns3}"

    kubectl run client2 --image=nginx:alpine -n "${ns2}"
    kubectl run client3 --image=nginx:alpine -n "${ns3}"

    kubectl wait --for=condition=Ready pod/client2 -n "${ns2}" --timeout=60s
    kubectl wait --for=condition=Ready pod/client3 -n "${ns3}" --timeout=60s

    # Apply allow-all-namespaces policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all-namespaces
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # All namespaces should be allowed
    local result2=0
    kubectl exec client2 -n "${ns2}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result2=$?
    assert_equal "${result2}" "0"

    local result3=0
    kubectl exec client3 -n "${ns3}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result3=$?
    assert_equal "${result3}" "0"

    # Cleanup
    kubectl delete namespace "${ns2}" --wait=false
    kubectl delete namespace "${ns3}" --wait=false
}

@test "05: Policy only affects pods with matching labels" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Create external namespace
    kubectl create namespace "${TEST_NS_OTHER}"
    kubectl run external-client --image=nginx:alpine -n "${TEST_NS_OTHER}"
    kubectl wait --for=condition=Ready pod/external-client -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply default-deny to all
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    # Apply allow-all-namespaces only to web
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all-namespaces
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')
    local api_ip=$(kubectl get pod api -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Web should be accessible from external namespace
    local result_web=0
    kubectl exec external-client -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_web=$?
    assert_equal "${result_web}" "0"

    # API should still be blocked (no policy allowing it)
    local result_api=0
    kubectl exec external-client -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${api_ip}:80" &>/dev/null || result_api=$?
    assert_not_equal "${result_api}" "0"
}

@test "05: namespaceSelector and podSelector in same from clause (AND logic)" {
    create_test_pod "web" "app=web"

    # Create labeled namespace
    kubectl create namespace "${TEST_NS_OTHER}"
    kubectl label namespace "${TEST_NS_OTHER}" env=test

    # Create pods with different labels
    kubectl run allowed-pod --image=nginx:alpine --labels="role=frontend" -n "${TEST_NS_OTHER}"
    kubectl run denied-pod --image=nginx:alpine --labels="role=backend" -n "${TEST_NS_OTHER}"

    kubectl wait --for=condition=Ready pod/allowed-pod -n "${TEST_NS_OTHER}" --timeout=60s
    kubectl wait --for=condition=Ready pod/denied-pod -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply policy requiring BOTH namespace label AND pod label
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-specific
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          env: test
      podSelector:
        matchLabels:
          role: frontend
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Pod with correct label should be allowed
    local result_allowed=0
    kubectl exec allowed-pod -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_allowed=$?
    assert_equal "${result_allowed}" "0"

    # Pod without correct label should be blocked
    local result_denied=0
    kubectl exec denied-pod -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result_denied=$?
    assert_not_equal "${result_denied}" "0"
}
