#!/usr/bin/env bash
# Integration test: Policy conflicts and precedence
# Tests how Kubernetes resolves conflicting policies

set -euo pipefail

test_overlapping_selectors() {
    local ns="integration-overlap-$$"
    echo "  [TEST] Policy conflicts: overlapping selectors"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Pod with multiple labels
    kubectl run app -n "$ns" --image=nginx --labels="app=web,tier=frontend,env=prod" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply multiple policies matching the same pod with different selectors
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-by-app
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
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-by-tier
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    sleep 5

    # Client should have access (union of both policies)
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Client should have access via policy union"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Overlapping selectors working (union behavior)"
    return 0
}

test_ingress_egress_conflict() {
    local ns="integration-inout-$$"
    echo "  [TEST] Policy conflicts: ingress vs egress"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run server -n "$ns" --image=nginx --labels="app=server" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/server pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local server_ip=$(kubectl get pod server -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policies: ingress allows, but egress denies
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
# Server allows ingress from client
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: server-ingress
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client
---
# Client denies all egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-egress
spec:
  podSelector:
    matchLabels:
      app: client
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
EOF

    sleep 5

    # Should be blocked (egress denial takes precedence)
    if kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${server_ip}" &>/dev/null; then
        echo "    FAIL: Egress denial should block traffic"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Ingress/egress conflict resolution working"
    return 0
}

test_policy_order_independence() {
    local ns="integration-order-$$"
    echo "  [TEST] Policy conflicts: order independence"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run client1 -n "$ns" --image=nginx --labels="role=a" --restart=Never 2>/dev/null || true
    kubectl run client2 -n "$ns" --image=nginx --labels="role=b" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client1 pod/client2 -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policies in arbitrary order
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-role-b
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
          role: b
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-role-a
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
          role: a
EOF

    sleep 5

    # Both should work (order doesn't matter)
    if ! kubectl exec client1 -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Client1 should have access"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    if ! kubectl exec client2 -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Client2 should have access"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Policy order independence verified"
    return 0
}

test_empty_selector_behavior() {
    local ns="integration-empty-$$"
    echo "  [TEST] Policy conflicts: empty selector matching"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app1 -n "$ns" --image=nginx --labels="app=one" --restart=Never 2>/dev/null || true
    kubectl run app2 -n "$ns" --image=nginx --labels="app=two" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app1 pod/app2 pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app1_ip=$(kubectl get pod app1 -n "$ns" -o jsonpath='{.status.podIP}')
    local app2_ip=$(kubectl get pod app2 -n "$ns" -o jsonpath='{.status.podIP}')

    # Empty podSelector {} matches all pods in namespace
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-pods
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    sleep 5

    # Both apps should be blocked
    if kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app1_ip}" &>/dev/null; then
        echo "    FAIL: App1 should be blocked by empty selector"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    if kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app2_ip}" &>/dev/null; then
        echo "    FAIL: App2 should be blocked by empty selector"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Empty selector behavior verified"
    return 0
}
