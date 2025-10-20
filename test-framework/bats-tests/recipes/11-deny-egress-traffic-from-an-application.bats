#!/usr/bin/env bats
# BATS tests for Recipe 11: Deny Egress Traffic from an Application
# Tests egress blocking policies

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-11-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "11: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/11-deny-egress-traffic-from-an-application.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "11: Policy should deny all egress traffic from target pod" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Egress should work before policy
    test_connectivity "web" "api" "allow"

    # Apply deny-egress policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # Egress should now be blocked
    test_connectivity "web" "api" "deny"
}

@test "11: Egress policy only affects pods with matching labels" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"

    # Apply deny-egress only to web
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # Web egress should be blocked
    test_connectivity "web" "api" "deny"

    # API egress should still work (no policy applied)
    test_connectivity "api" "db" "allow"
}

@test "11: Empty podSelector denies egress from all pods in namespace" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"

    # Apply namespace-wide egress deny
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # All egress should be blocked
    test_connectivity "web" "api" "deny"
    test_connectivity "api" "db" "deny"
    test_connectivity "db" "web" "deny"
}

@test "11: Egress-only policy does not affect ingress" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply egress-only policy to web
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # Egress from web should be blocked
    test_connectivity "web" "client" "deny"

    # Ingress to web should still work (no Ingress policy)
    test_connectivity "client" "web" "allow"
}

@test "11: Policy with both Ingress and Egress policyTypes" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"
    create_test_pod "api" "app=api"

    # Apply policy denying both ingress and egress
    kubectl apply -n "${TEST_NS}" -f - <<EOF
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
  - Egress
EOF

    wait_for_policy_enforcement

    # Ingress to web should be blocked
    test_connectivity "client" "web" "deny"

    # Egress from web should be blocked
    test_connectivity "web" "api" "deny"
}

@test "11: Egress policy can be verified via kubectl" {
    create_test_pod "web" "app=web"

    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    # Verify policy exists
    verify_network_policy "web-deny-egress"

    # Check policy details
    run get_policy_details "web-deny-egress"
    assert_success
    assert_output --partial "web-deny-egress"
    assert_output --partial "Egress"
}

@test "11: Egress policy blocks DNS resolution" {
    create_test_pod "web" "app=web"

    # Apply deny-egress policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # DNS should be blocked (no egress allowed)
    local result=0
    kubectl exec web -n "${TEST_NS}" -- \
        nslookup kubernetes.default &>/dev/null || result=$?

    assert_not_equal "${result}" "0" "DNS should be blocked"
}

@test "11: Combining egress deny with selective allow" {
    create_test_pod "web" "app=web"
    create_test_pod "allowed-api" "app=api,tier=backend"
    create_test_pod "denied-api" "app=other"

    # Apply deny-all egress first
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
EOF

    # Then apply selective allow
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-backend
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: backend
EOF

    wait_for_policy_enforcement

    # Egress to allowed-api should work (policies are OR'd)
    test_connectivity "web" "allowed-api" "allow"

    # Egress to denied-api should be blocked
    test_connectivity "web" "denied-api" "deny"
}
