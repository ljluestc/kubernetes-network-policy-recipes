#!/usr/bin/env bats
# BATS tests for Recipe 01: Deny All Traffic to an Application
# Tests default-deny ingress policy

load '../helpers/test_helper'

setup() {
    # Call parent setup
    TEST_NS="${TEST_NAMESPACE_PREFIX}-01-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"

    create_test_namespace
}

@test "01: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/01-deny-all-traffic-to-an-application.md"

    # Extract YAML from markdown
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")

    # Validate YAML syntax
    validate_yaml "${yaml_file}"
}

@test "01: Policy should deny all ingress traffic to target pod" {
    # Create target pod with app=web label
    create_test_pod "web" "app=web"

    # Create client pod
    create_test_pod "client" "app=client"

    # Traffic should work before policy
    test_connectivity "client" "web" "allow"

    # Apply deny-all policy
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
EOF

    # Wait for policy to take effect
    wait_for_policy_enforcement

    # Traffic should now be blocked
    test_connectivity "client" "web" "deny"
}

@test "01: Policy should only affect pods with matching labels" {
    # Create two web pods
    create_test_pod "web1" "app=web"
    create_test_pod "web2" "app=api"
    create_test_pod "client" "app=client"

    # Apply deny-all policy to app=web only
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
EOF

    wait_for_policy_enforcement

    # web1 (app=web) should be blocked
    test_connectivity "client" "web1" "deny"

    # web2 (app=api) should still be accessible
    test_connectivity "client" "web2" "allow"
}

@test "01: Empty podSelector should match all pods in namespace" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "client" "app=client"

    # Apply deny-all to entire namespace
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

    # All pods should be blocked
    test_connectivity "client" "web" "deny"
    test_connectivity "client" "api" "deny"
}

@test "01: Policy should be retrievable via kubectl" {
    create_test_pod "web" "app=web"

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
EOF

    # Verify policy exists
    verify_network_policy "web-deny-all"

    # Check policy details
    run get_policy_details "web-deny-all"
    assert_success
    assert_output --partial "web-deny-all"
    assert_output --partial "app: web"
}

@test "01: Egress traffic should not be affected by ingress-only policy" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

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
EOF

    wait_for_policy_enforcement

    # Ingress to web should be blocked
    test_connectivity "api" "web" "deny"

    # Egress from web should still work
    test_connectivity "web" "api" "allow"
}
