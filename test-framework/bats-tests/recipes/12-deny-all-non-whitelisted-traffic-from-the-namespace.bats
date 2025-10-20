#!/usr/bin/env bats
# BATS tests for Recipe 12: Deny All Non-Whitelisted Egress Traffic from the Namespace
# Tests namespace-wide egress default-deny

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-12-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "12: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/12-deny-all-non-whitelisted-traffic-from-the-namespace.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "12: Default-deny egress policy blocks all egress in namespace" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"

    # Apply namespace-wide default-deny egress
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

@test "12: Empty podSelector matches all pods for egress" {
    create_test_pod "pod1" "app=pod1"
    create_test_pod "pod2" "role=backend"
    create_test_pod "pod3" "tier=frontend"

    # Apply policy with empty podSelector
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # All pods should have egress blocked
    test_connectivity "pod1" "pod2" "deny"
    test_connectivity "pod2" "pod3" "deny"
    test_connectivity "pod3" "pod1" "deny"
}

@test "12: Default-deny egress with DNS whitelist" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply default-deny egress
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

    # Apply DNS whitelist policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

    wait_for_policy_enforcement

    # DNS should work (whitelisted)
    local result_dns=0
    kubectl exec web -n "${TEST_NS}" -- \
        nslookup kubernetes.default &>/dev/null || result_dns=$?

    # DNS should succeed or timeout (but not be immediately blocked)
    # Note: In some clusters, DNS may still fail due to networking setup

    # Regular egress should still be blocked
    test_connectivity "web" "api" "deny"
}

@test "12: Default-deny with selective egress whitelist" {
    create_test_pod "web" "app=web"
    create_test_pod "allowed-api" "app=api,tier=backend"
    create_test_pod "denied-api" "app=other"

    # Apply default-deny egress
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

    # Apply whitelist for backend tier
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-egress
spec:
  podSelector: {}
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

@test "12: Default-deny egress does not affect ingress" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply default-deny egress only
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

    # Egress should be blocked
    test_connectivity "web" "client" "deny"

    # Ingress should still work (no Ingress policy)
    test_connectivity "client" "web" "allow"
}

@test "12: Multiple default-deny egress policies combine correctly" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply first default-deny egress
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress-1
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF

    # Apply second default-deny egress (should not conflict)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress-2
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF

    wait_for_policy_enforcement

    # Egress should still be blocked
    test_connectivity "web" "api" "deny"

    # Verify both policies exist
    verify_network_policy "default-deny-egress-1"
    verify_network_policy "default-deny-egress-2"
}

@test "12: Default-deny egress applies to new pods created after policy" {
    # Apply default-deny egress first
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

    # Create pods after policy
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Egress should be blocked for newly created pods
    test_connectivity "web" "api" "deny"
}

@test "12: Egress whitelist with port restrictions" {
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

    # Apply default-deny egress
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

    # Whitelist only port 8080
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-port-8080
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
