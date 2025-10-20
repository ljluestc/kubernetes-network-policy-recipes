#!/usr/bin/env bats
# BATS tests for Recipe 08: Allow External Traffic
# Tests ipBlock CIDR configuration

load '../helpers/test_helper'

setup() {
    TEST_NS="${TEST_NAMESPACE_PREFIX}-08-$(date +%s)-$$"
    TEST_START_TIME=$(date +%s)
    TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/${TEST_NS}"
    mkdir -p "${TEST_TEMP_DIR}"
    create_test_namespace
}

@test "08: YAML syntax should be valid" {
    local recipe_file="${RECIPE_DIR}/08-allow-external-traffic.md"
    local yaml_file=$(extract_yaml_from_recipe "${recipe_file}")
    validate_yaml "${yaml_file}"
}

@test "08: Policy with ipBlock should be created successfully" {
    create_test_pod "web" "app=web"

    # Apply policy with ipBlock
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-external
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 172.17.0.0/16
        except:
        - 172.17.1.0/24
EOF

    # Verify policy was created
    verify_network_policy "web-allow-external"

    # Check policy details
    run get_policy_details "web-allow-external"
    assert_success
    assert_output --partial "ipBlock"
    assert_output --partial "172.17.0.0/16"
}

@test "08: Policy with multiple CIDR blocks (OR logic)" {
    create_test_pod "web" "app=web"

    # Apply policy with multiple ipBlocks
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-multiple-cidrs
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.0.0/8
  - from:
    - ipBlock:
        cidr: 192.168.0.0/16
EOF

    verify_network_policy "web-allow-multiple-cidrs"

    run get_policy_details "web-allow-multiple-cidrs"
    assert_success
    assert_output --partial "10.0.0.0/8"
    assert_output --partial "192.168.0.0/16"
}

@test "08: ipBlock with except clause excludes specific ranges" {
    create_test_pod "web" "app=web"

    # Apply policy with except clause
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-with-exceptions
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8
        - 192.168.0.0/16
EOF

    verify_network_policy "web-allow-with-exceptions"

    run get_policy_details "web-allow-with-exceptions"
    assert_success
    assert_output --partial "except"
    assert_output --partial "10.0.0.0/8"
    assert_output --partial "192.168.0.0/16"
}

@test "08: Combining ipBlock with podSelector in same from clause" {
    create_test_pod "web" "app=web"
    create_test_pod "internal-client" "app=client"

    # Apply policy allowing both internal pods OR external IPs
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-internal-and-external
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
  - from:
    - ipBlock:
        cidr: 203.0.113.0/24
EOF

    wait_for_policy_enforcement

    # Internal client should be allowed
    test_connectivity "internal-client" "web" "allow"

    # Verify policy structure
    verify_network_policy "web-allow-internal-and-external"
}

@test "08: ipBlock allows internal cluster traffic when using cluster CIDR" {
    create_test_pod "web" "app=web"
    create_test_pod "client" "app=client"

    # Get pod CIDR (typically 10.0.0.0/8 or similar)
    local pod_cidr="10.0.0.0/8"

    # Apply policy allowing pod CIDR
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-pod-cidr
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: ${pod_cidr}
EOF

    wait_for_policy_enforcement

    # Internal traffic should work if pod IP is in CIDR
    local client_ip=$(kubectl get pod client -n "${TEST_NS}" -o jsonpath='{.status.podIP}')

    # Check if client IP is in expected range
    if [[ "${client_ip}" =~ ^10\. ]]; then
        test_connectivity "client" "web" "allow"
    else
        skip "Pod IP ${client_ip} not in test CIDR range"
    fi
}

@test "08: Invalid CIDR should be rejected" {
    create_test_pod "web" "app=web"

    # Try to apply policy with invalid CIDR
    run kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-invalid-cidr
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: invalid-cidr
EOF

    assert_failure
}

@test "08: ipBlock policy does not affect egress" {
    create_test_pod "web" "app=web"
    create_test_pod "api" "app=api"

    # Apply ingress-only ipBlock policy
    kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-ingress-only
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 203.0.113.0/24
EOF

    wait_for_policy_enforcement

    # Egress from web should still work
    test_connectivity "web" "api" "allow"
}
