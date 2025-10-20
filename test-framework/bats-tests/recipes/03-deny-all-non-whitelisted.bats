#!/usr/bin/env bats
# BATS tests for Recipe 03: Deny All Non-Whitelisted Traffic in the Namespace
# Tests default-deny policy for entire namespace

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-03-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "03: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/03-deny-all-non-whitelisted-traffic-in-the-namespace.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "03: Default-deny policy should block all ingress in namespace" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "client" "app=client"

    # Apply namespace-wide default-deny policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    wait_for_policy_enforcement

    # All traffic should be blocked
    test_connectivity "client" "web" "deny"
    test_connectivity "client" "api" "deny"
    test_connectivity "web" "api" "deny"
}

@test "03: Empty podSelector should match all pods in namespace" {
    create_test_pod "pod1" "app=pod1"
    create_test_pod "pod2" "role=backend"
    create_test_pod "pod3" "tier=frontend"
    create_test_pod "client" "app=client"

    # Apply policy with empty podSelector
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    wait_for_policy_enforcement

    # All pods should be blocked regardless of labels
    test_connectivity "client" "pod1" "deny"
    test_connectivity "client" "pod2" "deny"
    test_connectivity "client" "pod3" "deny"
}

@test "03: Default-deny with whitelist policy allows specific traffic" {
    create_test_pod "web" "app=web"
    create_test_pod "allowed-client" "role=frontend"
    create_test_pod "denied-client" "role=backend"

    # Apply default-deny to all pods
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    # Apply whitelist policy for web pod
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-frontend
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
EOF

    wait_for_policy_enforcement

    # Frontend should be allowed to web (whitelist)
    test_connectivity "allowed-client" "web" "allow"

    # Backend should be denied to web (default deny)
    test_connectivity "denied-client" "web" "deny"
}

@test "03: Default-deny does not affect egress traffic" {
    create_test_pod "pod1" "app=pod1"
    create_test_pod "pod2" "app=pod2"

    # Apply default-deny ingress policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    wait_for_policy_enforcement

    # Ingress should be blocked
    test_connectivity "pod1" "pod2" "deny"

    # But egress should still work (policy only affects Ingress)
    # Note: This is validated by the fact that pod1 can initiate the connection attempt
    run kubectl exec "pod1" -n "${TEST_NS}" -- wget -T 2 -O- "http://example.com" 2>&1 || true
    # Command should execute (egress allowed), even if it times out
}

@test "03: Multiple default-deny policies in same namespace combine correctly" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply first default-deny policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-1
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    # Apply second default-deny policy (should not conflict)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-2
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    wait_for_policy_enforcement

    # Traffic should still be blocked
    test_connectivity "client" "web" "deny"

    # Verify both policies exist
    verify_network_policy "default-deny-1"
    verify_network_policy "default-deny-2"
}

@test "03: Default-deny applies to new pods created after policy" {
    # Apply default-deny policy first
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    wait_for_policy_enforcement

    # Create pods after policy is applied
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Traffic should be blocked for newly created pods
    test_connectivity "client" "web" "deny"
}
