#!/usr/bin/env bats
# BATS tests for Recipe 14: Deny External Egress Traffic
# Tests blocking external egress while allowing internal traffic

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-14-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "14: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/14-deny-external-egress-traffic.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "14: Policy should allow internal egress but block external" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply policy allowing only internal pod traffic
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-external-egress
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

    # Internal egress should work
    test_connectivity "web" "api" "allow"

    # External egress should be blocked
    local result_external=0
    kubectl exec web -n "${TEST_NS}" -- \
        wget -T 2 -O- "http://example.com" &>/dev/null || result_external=$?
    assert_not_equal "${result_external}" "0" "External egress should be blocked"
}

@test "14: Policy allows egress to all pods in same namespace" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"
    create_test_pod "cache" "app=cache"

    # Apply policy with empty podSelector
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal-only
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    # All internal traffic should work
    test_connectivity "web" "api" "allow"
    test_connectivity "api" "db" "allow"
    test_connectivity "db" "cache" "allow"
}

@test "14: Policy with DNS and internal traffic allowed" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply policy allowing internal traffic and DNS
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal-and-dns
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

    wait_for_policy_enforcement

    # Internal traffic should work
    test_connectivity "web" "api" "allow"

    # External traffic should still be blocked (even though DNS is allowed)
    local result_external=0
    kubectl exec web -n "${TEST_NS}" -- \
        wget -T 2 -O- "http://example.com" &>/dev/null || result_external=$?
    assert_not_equal "${result_external}" "0"
}

@test "14: Policy blocks egress to other namespaces" {
    create_test_pod "web" "app=web"

    # Create external namespace
    local ns_other="${TEST_NS}-other"
    kubectl create namespace "${ns_other}"
    kubectl run external-pod --image=nginx:alpine -n "${ns_other}"
    kubectl wait --for=condition=Ready pod/external-pod -n "${ns_other}" --timeout=60s

    # Apply policy allowing only same-namespace egress
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    local external_ip=$(kubectl get pod external-pod -n "${ns_other}" -o jsonpath='{.status.podIP}')

    # Egress to other namespace should be blocked
    local result=0
    kubectl exec web -n "${TEST_NS}" -- \
        wget -T 2 -O- "http://${external_ip}:80" &>/dev/null || result=$?
    assert_not_equal "${result}" "0" "Cross-namespace egress should be blocked"

    # Cleanup
    kubectl delete namespace "${ns_other}" --wait=false
}

@test "14: Policy with ipBlock to allow specific external CIDR" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Get cluster pod CIDR
    local pod_cidr="10.0.0.0/8"

    # Apply policy allowing internal pods and specific external CIDR
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal-and-cidr
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24
EOF

    wait_for_policy_enforcement

    # Internal traffic should work
    test_connectivity "web" "api" "allow"

    # General external traffic should be blocked
    local result=0
    kubectl exec web -n "${TEST_NS}" -- \
        wget -T 2 -O- "http://example.com" &>/dev/null || result=$?
    assert_not_equal "${result}" "0"
}

@test "14: Namespace-wide policy applies to all pods" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"
    create_test_pod "db" "app=db"

    # Apply namespace-wide policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-all
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
EOF

    wait_for_policy_enforcement

    # All internal traffic should work
    test_connectivity "web" "api" "allow"
    test_connectivity "api" "db" "allow"

    # External traffic from any pod should be blocked
    for pod in web api db; do
        local result=0
        kubectl exec "${pod}" -n "${TEST_NS}" -- \
            wget -T 2 -O- "http://example.com" &>/dev/null || result=$?
        assert_not_equal "${result}" "0" "External egress from ${pod} should be blocked"
    done
}

@test "14: Policy does not affect ingress traffic" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply egress-only policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-egress
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

    # Ingress to web should still work (no Ingress policy)
    test_connectivity "client" "web" "allow"
}

@test "14: Policy with port-specific internal allow" {
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

    # Apply policy allowing only specific port internally
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-internal-8080
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
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
