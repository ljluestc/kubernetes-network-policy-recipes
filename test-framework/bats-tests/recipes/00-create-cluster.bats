#!/usr/bin/env bats
# BATS tests for Recipe 00: Create Cluster
# Tests cluster creation and NetworkPolicy support validation

load '../helpers/test_helper'

@test "00: Cluster should have NetworkPolicy API available" {
    run kubectl api-versions
    assert_success
    assert_output --partial "networking.k8s.io/v1"
}

@test "00: Cluster should have nodes in Ready state" {
    run kubectl get nodes
    assert_success
    assert_output --partial "Ready"
}

@test "00: Kube-system namespace should exist" {
    run kubectl get namespace kube-system
    assert_success
}

@test "00: CNI plugin pods should be running" {
    # Check for common CNI plugins
    run kubectl get pods -n kube-system
    assert_success

    # At least one CNI should be present: calico, cilium, weave, flannel, etc.
    if kubectl get pods -n kube-system -l k8s-app=calico-node &>/dev/null; then
        run kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{.items[0].status.phase}'
        assert_output "Running"
    elif kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null; then
        run kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].status.phase}'
        assert_output "Running"
    elif kubectl get pods -n kube-system -l name=weave-net &>/dev/null; then
        run kubectl get pods -n kube-system -l name=weave-net -o jsonpath='{.items[0].status.phase}'
        assert_output "Running"
    else
        # For kind/minikube without explicit CNI
        skip "CNI pod detection - using default networking"
    fi
}

@test "00: Cluster should support NetworkPolicy creation" {
    create_test_namespace

    # Create a test NetworkPolicy
    run kubectl apply -n "${TEST_NS}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-policy
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
    assert_success

    # Verify policy was created
    run kubectl get networkpolicy test-policy -n "${TEST_NS}"
    assert_success
}

@test "00: Cluster should support pod creation" {
    create_test_namespace

    run kubectl run test-pod --image=nginx:alpine -n "${TEST_NS}"
    assert_success

    run kubectl wait --for=condition=Ready pod/test-pod -n "${TEST_NS}" --timeout=60s
    assert_success
}
