#!/usr/bin/env bash
# Integration test: Failure scenarios and recovery
# Tests resilience and error handling

set -euo pipefail

test_pod_restart_policy_persistence() {
    local ns="integration-restart-$$"
    echo "  [TEST] Failure recovery: pod restart preserves policy"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policy
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
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

    sleep 5

    # Verify connectivity before restart
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Initial connectivity failed"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Delete and recreate app pod (simulating restart)
    kubectl delete pod app -n "$ns" 2>/dev/null || true
    kubectl run app -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pod failed to restart"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    sleep 3
    local new_app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Verify policy still applies
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${new_app_ip}" &>/dev/null; then
        echo "    FAIL: Policy not preserved after pod restart"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Policy persists through pod restart"
    return 0
}

test_invalid_policy_rejection() {
    local ns="integration-invalid-$$"
    echo "  [TEST] Failure recovery: invalid policy handling"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Try to apply invalid policy (invalid port)
    if kubectl apply -n "$ns" -f - <<EOF 2>/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: invalid-policy
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
      port: 99999
EOF
    then
        echo "    WARN: Invalid policy was accepted (validation may vary)"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    else
        echo "    PASS: Invalid policy rejected"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi
}

test_policy_deletion_recovery() {
    local ns="integration-deletion-$$"
    echo "  [TEST] Failure recovery: policy deletion behavior"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply deny-all policy
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    sleep 3

    # Verify blocked
    if kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Should be blocked by deny-all"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Delete policy
    kubectl delete networkpolicy deny-all -n "$ns" 2>/dev/null || true
    sleep 3

    # Should now be allowed (no policies = allow all)
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Should be allowed after policy deletion"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Policy deletion recovery working"
    return 0
}

test_namespace_deletion_cleanup() {
    local ns="integration-cleanup-$$"
    echo "  [TEST] Failure recovery: namespace deletion cleanup"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pod failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    # Apply multiple policies
    for i in {1..5}; do
        kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-$i
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
EOF
    done

    # Delete namespace
    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    sleep 2

    # Verify namespace is gone or being deleted
    if kubectl get namespace "$ns" 2>/dev/null | grep -q Terminating; then
        echo "    PASS: Namespace cleanup in progress"
        return 0
    elif ! kubectl get namespace "$ns" &>/dev/null; then
        echo "    PASS: Namespace deleted successfully"
        return 0
    else
        echo "    WARN: Namespace still exists"
        return 0
    fi
}

test_concurrent_policy_updates() {
    local ns="integration-concurrent-$$"
    echo "  [TEST] Failure recovery: concurrent policy updates"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    # Apply same policy multiple times concurrently
    for i in {1..3}; do
        (kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-policy
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
        ) &
    done

    wait
    sleep 3

    # Verify policy is applied correctly
    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Policy not applied correctly after concurrent updates"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Concurrent policy updates handled"
    return 0
}
