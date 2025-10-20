#!/usr/bin/env bats
# BATS tests for Recipe 02a: Allow All Traffic to an Application
# Tests explicit allow-all policy

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-02a-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "02a: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/02a-allow-all-traffic-to-an-application.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "02a: Allow-all policy should permit traffic from any pod" {
    create_test_pod "web" "app=web"
    create_test_pod "client1" "app=client1"
    create_test_pod "client2" "app=client2"
    create_test_pod "client3" "role=monitoring"

    # Apply allow-all policy
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

    # All clients should be allowed
    test_connectivity "client1" "web" "allow"
    test_connectivity "client2" "web" "allow"
    test_connectivity "client3" "web" "allow"
}

@test "02a: Allow-all policy overrides previous deny policy" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # First apply deny-all policy
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

    # Traffic should be blocked
    test_connectivity "client" "web" "deny"

    # Now apply allow-all policy
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

    # Traffic should now be allowed (policies are combined with OR)
    test_connectivity "client" "web" "allow"
}

@test "02a: Empty ingress list vs ingress with empty object" {
    create_test_pod "deny-pod" "app=deny"
    create_test_pod "allow-pod" "app=allow"
    create_test_pod "client" "app=client"

    # Apply deny-all (empty ingress list)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector:
    matchLabels:
      app: deny
  policyTypes:
  - Ingress
EOF

    # Apply allow-all (ingress with empty object)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
spec:
  podSelector:
    matchLabels:
      app: allow
  policyTypes:
  - Ingress
  ingress:
  - {}
EOF

    wait_for_policy_enforcement

    # deny-pod should block traffic
    test_connectivity "client" "deny-pod" "deny"

    # allow-pod should allow traffic
    test_connectivity "client" "allow-pod" "allow"
}

@test "02a: Allow-all ingress does not affect egress" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply allow-all ingress policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all-ingress
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

    # Ingress should be allowed
    test_connectivity "client" "web" "allow"

    # Egress from web should still work (no egress policy)
    test_connectivity "web" "client" "allow"
}

@test "02a: Policy should only affect pods with matching labels" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "client" "app=client"

    # Apply deny-all to api
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-deny-all
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
EOF

    # Apply allow-all to web only
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

    # web should be allowed
    test_connectivity "client" "web" "allow"

    # api should still be denied
    test_connectivity "client" "api" "deny"
}
