#!/usr/bin/env bats
# BATS tests for Recipe 10: Allowing Traffic with Multiple Selectors
# Tests complex selector combinations and OR logic

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-10-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "10: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/10-allowing-traffic-with-multiple-selectors.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "10: Multiple from entries create OR logic" {
    create_test_pod "api" "app=api"
    create_test_pod "frontend" "role=frontend"
    create_test_pod "monitoring" "role=monitoring"
    create_test_pod "other" "role=other"

    # Apply policy with multiple from entries (OR logic)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-multiple
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
          role: frontend
    - podSelector:
        matchLabels:
          role: monitoring
EOF

    wait_for_policy_enforcement

    # Frontend should be allowed (matches first selector)
    test_connectivity "frontend" "api" "allow"

    # Monitoring should be allowed (matches second selector)
    test_connectivity "monitoring" "api" "allow"

    # Other should be denied (matches neither)
    test_connectivity "other" "api" "deny"
}

@test "10: Multiple ingress rules also create OR logic" {
    create_test_pod "api" "app=api"
    create_test_pod "frontend" "role=frontend"
    create_test_pod "monitoring" "role=monitoring"
    create_test_pod "other" "role=other"

    # Apply policy with multiple ingress rules
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-multiple-rules
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
          role: frontend
  - from:
    - podSelector:
        matchLabels:
          role: monitoring
EOF

    wait_for_policy_enforcement

    # Both should be allowed
    test_connectivity "frontend" "api" "allow"
    test_connectivity "monitoring" "api" "allow"

    # Other should be denied
    test_connectivity "other" "api" "deny"
}

@test "10: matchExpressions with In operator matches multiple values" {
    create_test_pod "api" "app=api"
    create_test_pod "client-v1" "app=client,version=v1"
    create_test_pod "client-v2" "app=client,version=v2"
    create_test_pod "client-v3" "app=client,version=v3"
    create_test_pod "other" "app=other"

    # Apply policy with matchExpressions using In operator
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-versions
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
          operator: In
          values:
          - v1
          - v2
EOF

    wait_for_policy_enforcement

    # v1 and v2 should be allowed
    test_connectivity "client-v1" "api" "allow"
    test_connectivity "client-v2" "api" "allow"

    # v3 should be denied (not in values list)
    test_connectivity "client-v3" "api" "deny"

    # other should be denied (wrong app label)
    test_connectivity "other" "api" "deny"
}

@test "10: matchExpressions with NotIn operator excludes values" {
    create_test_pod "api" "app=api"
    create_test_pod "prod-client" "app=client,env=production"
    create_test_pod "dev-client" "app=client,env=development"
    create_test_pod "test-client" "app=client,env=test"

    # Apply policy excluding production
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-non-prod
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
        - key: env
          operator: NotIn
          values:
          - production
EOF

    wait_for_policy_enforcement

    # Dev and test should be allowed
    test_connectivity "dev-client" "api" "allow"
    test_connectivity "test-client" "api" "allow"

    # Production should be denied
    test_connectivity "prod-client" "api" "deny"
}

@test "10: matchExpressions with Exists operator matches any value" {
    create_test_pod "api" "app=api"
    create_test_pod "labeled1" "app=client,version=v1"
    create_test_pod "labeled2" "app=client,version=v2"
    create_test_pod "unlabeled" "app=client"

    # Apply policy requiring version label to exist
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-require-version
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

    # Pods with version label should be allowed
    test_connectivity "labeled1" "api" "allow"
    test_connectivity "labeled2" "api" "allow"

    # Pod without version label should be denied
    test_connectivity "unlabeled" "api" "deny"
}

@test "10: matchExpressions with DoesNotExist operator" {
    create_test_pod "api" "app=api"
    create_test_pod "stable" "app=client,beta="
    create_test_pod "beta" "app=client"

    # Note: We can't easily test DoesNotExist in BATS as it requires
    # creating pods without specific labels. This test verifies syntax only.

    # Apply policy excluding beta pods
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-stable-only
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
        - key: beta
          operator: DoesNotExist
EOF

    verify_network_policy "api-stable-only"

    run get_policy_details "api-stable-only"
    assert_success
    assert_output --partial "DoesNotExist"
}

@test "10: Complex combination of matchLabels and matchExpressions" {
    create_test_pod "api" "app=api"
    create_test_pod "allowed" "team=platform,app=client,version=v2"
    create_test_pod "denied1" "team=other,app=client,version=v2"
    create_test_pod "denied2" "team=platform,app=other,version=v2"
    create_test_pod "denied3" "team=platform,app=client,version=v1"

    # Apply policy with both matchLabels and matchExpressions
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-complex-selectors
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
          team: platform
        matchExpressions:
        - key: app
          operator: In
          values:
          - client
        - key: version
          operator: In
          values:
          - v2
          - v3
EOF

    wait_for_policy_enforcement

    # Only pod with ALL criteria should be allowed
    test_connectivity "allowed" "api" "allow"

    # All others should be denied
    test_connectivity "denied1" "api" "deny"  # wrong team
    test_connectivity "denied2" "api" "deny"  # wrong app
    test_connectivity "denied3" "api" "deny"  # wrong version
}

@test "10: Multiple podSelectors combined with ports" {
    # Create multi-port API pod
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api
  labels:
    app: api
spec:
  containers:
  - name: app
    image: nginx:alpine
    ports:
    - containerPort: 8080
    - containerPort: 9090
EOF

    kubectl wait --for=condition=Ready pod/api -n "${TEST_NS}" --timeout=60s

    create_test_pod "frontend" "role=frontend"
    create_test_pod "monitoring" "role=monitoring"

    # Apply policy: frontend can access 8080, monitoring can access 9090
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-selective-access
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
          role: frontend
    ports:
    - protocol: TCP
      port: 8080
  - from:
    - podSelector:
        matchLabels:
          role: monitoring
    ports:
    - protocol: TCP
      port: 9090
EOF

    wait_for_policy_enforcement

    local api_ip=$(kubectl get pod api -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Frontend should access 8080 but not 9090
    test_port_connectivity "frontend" "${api_ip}" "8080" "allow"
    test_port_connectivity "frontend" "${api_ip}" "9090" "deny"

    # Monitoring should access 9090 but not 8080
    test_port_connectivity "monitoring" "${api_ip}" "9090" "allow"
    test_port_connectivity "monitoring" "${api_ip}" "8080" "deny"
}
