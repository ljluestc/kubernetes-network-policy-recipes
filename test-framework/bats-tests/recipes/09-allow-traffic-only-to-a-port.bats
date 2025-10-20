#!/usr/bin/env bats
# BATS tests for Recipe 09: Allow Traffic Only to a Port
# Tests port-specific network policies

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-09-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "09: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/09-allow-traffic-only-to-a-port.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "09: Policy should allow traffic only to specific port" {
    # Create web pod with multiple ports
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
      name: http
    - containerPort: 443
      name: https
EOF

    kubectl wait --for=condition=Ready pod/web -n "${TEST_NS}" --timeout=60s

    create_test_pod "client" "app=client"

    # Apply policy allowing only port 80
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-80
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
          app: client
    ports:
    - protocol: TCP
      port: 80
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Port 80 should be allowed
    test_port_connectivity "client" "${web_ip}" "80" "allow"

    # Port 443 should be blocked (not explicitly allowed)
    test_port_connectivity "client" "${web_ip}" "443" "deny"
}

@test "09: Policy can allow multiple specific ports" {
    # Create multi-port pod
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
    - containerPort: 8081
    - containerPort: 9090
EOF

    kubectl wait --for=condition=Ready pod/api -n "${TEST_NS}" --timeout=60s

    create_test_pod "client" "app=client"

    # Apply policy allowing ports 8080 and 8081
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-multiple-ports
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
          app: client
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 8081
EOF

    wait_for_policy_enforcement

    local api_ip=$(kubectl get pod api -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # 8080 should be allowed
    test_port_connectivity "client" "${api_ip}" "8080" "allow"

    # 8081 should be allowed
    test_port_connectivity "client" "${api_ip}" "8081" "allow"

    # 9090 should be blocked
    test_port_connectivity "client" "${api_ip}" "9090" "deny"
}

@test "09: Policy supports UDP protocol" {
    create_test_pod "dns" "app=dns"
    create_test_pod "client" "app=client"

    # Apply policy allowing UDP port 53
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dns-allow-udp
spec:
  podSelector:
    matchLabels:
      app: dns
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client
    ports:
    - protocol: UDP
      port: 53
EOF

    verify_network_policy "dns-allow-udp"

    run get_policy_details "dns-allow-udp"
    assert_success
    assert_output --partial "protocol: UDP"
    assert_output --partial "port: 53"
}

@test "09: Port without protocol defaults to TCP" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Apply policy without specifying protocol
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-default-protocol
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
          app: client
    ports:
    - port: 80
EOF

    verify_network_policy "web-default-protocol"

    # Should default to TCP
    run get_policy_details "web-default-protocol"
    assert_success
    assert_output --partial "port: 80"
}

@test "09: Ports can be specified with different selectors" {
    create_test_pod "api" "app=api"
    create_test_pod "admin" "role=admin"
    create_test_pod "user" "role=user"

    # Apply policy with different port access for different sources
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-selective-ports
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
          role: admin
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 9090
  - from:
    - podSelector:
        matchLabels:
          role: user
    ports:
    - protocol: TCP
      port: 8080
EOF

    wait_for_policy_enforcement

    local api_ip=$(kubectl get pod api -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Admin should access both ports
    test_port_connectivity "admin" "${api_ip}" "8080" "allow"
    test_port_connectivity "admin" "${api_ip}" "9090" "allow"

    # User should only access 8080
    test_port_connectivity "user" "${api_ip}" "8080" "allow"
    test_port_connectivity "user" "${api_ip}" "9090" "deny"
}

@test "09: Empty ports list allows all ports" {
    # Create multi-port pod
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
    - containerPort: 443
    - containerPort: 8080
EOF

    kubectl wait --for=condition=Ready pod/web -n "${TEST_NS}" --timeout=60s

    create_test_pod "client" "app=client"

    # Apply policy without ports specification (allows all ports)
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all-ports
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
          app: client
EOF

    wait_for_policy_enforcement

    local web_ip=$(kubectl get pod web -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # All ports should be allowed
    test_port_connectivity "client" "${web_ip}" "80" "allow"
    test_port_connectivity "client" "${web_ip}" "443" "allow"
    test_port_connectivity "client" "${web_ip}" "8080" "allow"
}

@test "09: Port policy does not affect egress" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply ingress port policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-port-80-only
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 80
EOF

    wait_for_policy_enforcement

    # Egress from web should still work
    test_connectivity "web" "api" "allow"
}
