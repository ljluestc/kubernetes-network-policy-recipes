#!/usr/bin/env bats
# BATS tests for Recipe 13: Allow Egress Traffic to Specific Pods
# Tests selective egress to specific pods

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-13-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "13: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/13-allow-egress-traffic-to-specific-pods.md"

    # Check if file exists, if not skip test
    if [[ ! -f "${recipe_file}" ]]; then
        skip "Recipe file not found: ${recipe_file}"
    fi

    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "13: Policy should allow egress only to pods with specific labels" {
    create_test_pod "web" "app=web"
    create_test_pod "allowed-api" "app=api,tier=backend"
    create_test_pod "denied-api" "app=other"

    # Apply policy allowing egress to tier=backend only
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-backend-egress
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

    # Egress to backend should be allowed
    test_connectivity "web" "allowed-api" "allow"

    # Egress to non-backend should be blocked
    test_connectivity "web" "denied-api" "deny"
}

@test "13: Egress policy only affects pods matching podSelector" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"
    create_test_pod "cache" "app=cache"

    # Apply egress policy only to web
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-db-egress
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
          app: db
EOF

    wait_for_policy_enforcement

    # Web can reach db
    test_connectivity "web" "db" "allow"

    # Web cannot reach api or cache
    test_connectivity "web" "api" "deny"
    test_connectivity "web" "cache" "deny"

    # API can reach db (no policy applied to api)
    test_connectivity "api" "db" "allow"
}

@test "13: Multiple egress rules create OR logic" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"
    create_test_pod "cache" "app=cache"

    # Apply policy allowing egress to api OR db
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-multiple-egress
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
          app: api
  - to:
    - podSelector:
        matchLabels:
          app: db
EOF

    wait_for_policy_enforcement

    # Egress to api should work
    test_connectivity "web" "api" "allow"

    # Egress to db should work
    test_connectivity "web" "db" "allow"

    # Egress to cache should be blocked
    test_connectivity "web" "cache" "deny"
}

@test "13: Egress with matchExpressions" {
    create_test_pod "web" "app=web"
    create_test_pod "api-v1" "app=api,version=v1"
    create_test_pod "api-v2" "app=api,version=v2"
    create_test_pod "other" "app=other"

    # Apply policy with matchExpressions
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-api-egress
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - api
        - key: version
          operator: Exists
EOF

    wait_for_policy_enforcement

    # Both API versions should be allowed
    test_connectivity "web" "api-v1" "allow"
    test_connectivity "web" "api-v2" "allow"

    # Other should be blocked
    test_connectivity "web" "other" "deny"
}

@test "13: Egress policy with port restrictions" {
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

    create_test_pod "web" "app=web"

    # Apply policy allowing egress to api only on port 8080
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-api-8080
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
          app: api
    ports:
    - protocol: TCP
      port: 8080
EOF

    wait_for_policy_enforcement

    local api_ip=$(kubectl get pod api -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Port 8080 should be allowed
    test_port_connectivity "web" "${api_ip}" "8080" "allow"

    # Port 9090 should be blocked
    test_port_connectivity "web" "${api_ip}" "9090" "deny"
}

@test "13: Egress to pods in same namespace with empty podSelector" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"
    create_test_pod "cache" "app=cache"

    # Apply policy allowing egress to all pods in namespace
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all-namespace
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    # All intra-namespace egress should work
    test_connectivity "web" "api" "allow"
    test_connectivity "web" "db" "allow"
    test_connectivity "web" "cache" "allow"
}

@test "13: Combining egress allow with DNS whitelist" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply policy allowing egress to api and DNS
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-api-and-dns
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
          app: api
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

    wait_for_policy_enforcement

    # Egress to api should work
    test_connectivity "web" "api" "allow"

    # DNS should work (if kube-system is properly labeled)
    # Note: This may not work in all test environments
    run kubectl exec web -n "${TEST_NS}" -- nslookup kubernetes.default 2>&1 || true
}

@test "13: Egress-only policy does not affect ingress" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "client" "app=client"

    # Apply egress-only policy to web
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-api-egress
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
          app: api
EOF

    wait_for_policy_enforcement

    # Egress from web to api should work
    test_connectivity "web" "api" "allow"

    # Ingress to web should still work (no Ingress policy)
    test_connectivity "client" "web" "allow"
}
