#!/usr/bin/env bats
# BATS tests for Recipe 02: Limit Traffic to an Application
# Tests selective allow from specific pods

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-02-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "02: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/02-limit-traffic-to-an-application.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "02: Policy should allow traffic from pods with specific labels" {
    # Create target pod
    create_test_pod "web" "app=bookstore,role=api"

    # Create allowed client pod
    create_test_pod "allowed-client" "app=bookstore,role=search"

    # Create denied client pod
    create_test_pod "denied-client" "app=other"

    # Apply policy allowing traffic from app=bookstore
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: bookstore
EOF

    wait_for_policy_enforcement

    # Allowed client should succeed
    test_connectivity "allowed-client" "web" "allow"

    # Denied client should be blocked
    test_connectivity "denied-client" "web" "deny"
}

@test "02: Policy with multiple ingress rules should allow traffic from any matching rule (OR logic)" {
    create_test_pod "web" "app=web"
    create_test_pod "frontend" "role=frontend"
    create_test_pod "monitoring" "role=monitoring"
    create_test_pod "other" "role=other"

    # Apply policy with multiple ingress sources (OR logic)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-multiple
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
  - from:
    - podSelector:
        matchLabels:
          role: monitoring
EOF

    wait_for_policy_enforcement

    # Both frontend and monitoring should be allowed
    test_connectivity "frontend" "web" "allow"
    test_connectivity "monitoring" "web" "allow"

    # Other should be blocked
    test_connectivity "other" "web" "deny"
}

@test "02: Policy should only affect pods matching podSelector" {
    create_test_pod "api" "app=api"
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply policy only to app=api
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
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

    # api should only allow from web
    test_connectivity "web" "api" "allow"
    test_connectivity "client" "api" "deny"

    # web should still be fully accessible (no policy applied)
    test_connectivity "client" "web" "allow"
}

@test "02: Complex matchExpressions should work correctly" {
    create_test_pod "api" "app=api"
    create_test_pod "client-v1" "app=client,version=v1"
    create_test_pod "client-v2" "app=client,version=v2"
    create_test_pod "other" "app=other"

    # Apply policy with matchExpressions
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-expression
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - client
        - key: version
          operator: Exists
EOF

    wait_for_policy_enforcement

    # Both client versions should be allowed
    test_connectivity "client-v1" "api" "allow"
    test_connectivity "client-v2" "api" "allow"

    # Other should be blocked
    test_connectivity "other" "api" "deny"
}

@test "02: Empty ingress rule allows all traffic" {
    create_test_pod "web" "app=web"
    create_test_pod "client1" "app=client1"
    create_test_pod "client2" "app=client2"

    # Apply policy with empty from clause
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - {}
EOF

    wait_for_policy_enforcement

    # All pods should be allowed
    test_connectivity "client1" "web" "allow"
    test_connectivity "client2" "web" "allow"
}
