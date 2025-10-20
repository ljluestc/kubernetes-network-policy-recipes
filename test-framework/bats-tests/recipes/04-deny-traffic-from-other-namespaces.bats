#!/usr/bin/env bats
# BATS tests for Recipe 04: Deny Traffic from Other Namespaces
# Tests namespace isolation policy

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-04-$(date +%s)-$$"
    TEST_NS_OTHER="${TEST_NS}-other"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

teardown() {
    # Cleanup both namespaces
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    echo "# Test duration: ${duration}s" >&3

    kubectl delete namespace "${TEST_NS}" --wait=true --timeout=30s 2>/dev/null || true
    kubectl delete namespace "${TEST_NS_OTHER}" --wait=true --timeout=30s 2>/dev/null || true

    rm -rf "${TEST_TEMP_DIR}"
}

@test "04: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/04-deny-traffic-from-other-namespaces.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "04: Policy should deny traffic from other namespaces" {
    # Create web pod in primary namespace
    create_test_pod "web" "app=web"

    # Create client in same namespace
    create_test_pod "internal-client" "app=client"

    # Create second namespace and client
    kubectl create namespace "${TEST_NS_OTHER}"
    kubectl run external-client --image=nginx:alpine -n "${TEST_NS_OTHER}"
    kubectl wait --for=condition=Ready pod/external-client -n "${TEST_NS_OTHER}" --timeout=60s

    # Apply policy denying traffic from other namespaces
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    # Get web pod IP
    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Internal traffic should work
    test_connectivity "internal-client" "web" "allow"

    # External traffic from other namespace should be blocked
    local result=0
    kubectl exec external-client -n "${TEST_NS_OTHER}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result=$?

    assert_not_equal "${result}" "0" "Cross-namespace traffic should be blocked"
}

@test "04: Policy allows intra-namespace communication" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"

    # Apply policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    # All intra-namespace traffic should work
    test_connectivity "web" "api" "allow"
    test_connectivity "api" "db" "allow"
    test_connectivity "db" "web" "allow"
}

@test "04: Empty podSelector in from clause allows all pods in same namespace" {
    create_test_pod "web" "app=web"
    create_test_pod "client1" "role=frontend"
    create_test_pod "client2" "role=backend"
    create_test_pod "client3" "tier=cache"

    # Apply policy with empty podSelector in from
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    # All pods in same namespace should be allowed
    test_connectivity "client1" "web" "allow"
    test_connectivity "client2" "web" "allow"
    test_connectivity "client3" "web" "allow"
}

@test "04: Policy blocks traffic from multiple other namespaces" {
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

    # Apply policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Both external namespaces should be blocked
    local result2=0
    kubectl exec client2 -n "${ns2}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result2=$?
    assert_not_equal "${result2}" "0"

    local result3=0
    kubectl exec client3 -n "${ns3}" -- \
        wget -T 2 -O- "http://${web_ip}:80" &>/dev/null || result3=$?
    assert_not_equal "${result3}" "0"

    # Cleanup
    kubectl delete namespace "${ns2}" --wait=false
    kubectl delete namespace "${ns3}" --wait=false
}

@test "04: Policy can be combined with pod-specific selectors" {
    create_test_pod "api" "app=api"
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply policy allowing only web pods in same namespace
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-web-only
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
EOF

    wait_for_policy_enforcement

    # Web should be allowed
    test_connectivity "web" "api" "allow"

    # Client should be blocked
    test_connectivity "client" "api" "deny"
}
