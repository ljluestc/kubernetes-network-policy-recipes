#!/usr/bin/env bash
# Integration test: Multi-policy combinations
# Tests complex interactions between multiple network policies

set -euo pipefail

test_deny_all_plus_selective_allow() {
    local ns="integration-multi-policy-$$"
    echo "  [TEST] Multi-policy: deny-all + selective allow"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Deploy 3 pods
    kubectl run web -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run api -n "$ns" --image=nginx --labels="app=api" --restart=Never 2>/dev/null || true
    kubectl run db -n "$ns" --image=nginx --labels="app=db" --restart=Never 2>/dev/null || true

    # Wait for pods with timeout
    if ! kubectl wait --for=condition=Ready pod/web pod/api pod/db -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local web_ip=$(kubectl get pod web -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply deny-all policy
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    sleep 5

    # Verify all traffic blocked
    if kubectl exec api -n "$ns" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: Traffic should be blocked by deny-all"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Apply selective allow for web from api
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-api
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
EOF

    sleep 5

    # Verify api can reach web
    if ! kubectl exec api -n "$ns" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: API should reach web after selective allow"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Verify db still blocked
    if kubectl exec db -n "$ns" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: DB should still be blocked"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Multi-policy combination working correctly"
    return 0
}

test_multiple_ingress_rules() {
    local ns="integration-multi-ingress-$$"
    echo "  [TEST] Multi-policy: multiple ingress rules"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Deploy pods
    kubectl run app -n "$ns" --image=nginx --labels="app=myapp" --restart=Never 2>/dev/null || true
    kubectl run client1 -n "$ns" --image=nginx --labels="role=frontend" --restart=Never 2>/dev/null || true
    kubectl run client2 -n "$ns" --image=nginx --labels="role=backend" --restart=Never 2>/dev/null || true
    kubectl run client3 -n "$ns" --image=nginx --labels="role=other" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client1 pod/client2 pod/client3 -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policy with multiple ingress rules
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-multi-ingress
spec:
  podSelector:
    matchLabels:
      app: myapp
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
          role: backend
EOF

    sleep 5

    # Test frontend access (should work)
    if ! kubectl exec client1 -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Frontend should access app"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Test backend access (should work)
    if ! kubectl exec client2 -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Backend should access app"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Test other access (should be blocked)
    if kubectl exec client3 -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Other role should be blocked"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Multiple ingress rules working correctly"
    return 0
}

test_policy_priority_and_precedence() {
    local ns="integration-priority-$$"
    echo "  [TEST] Multi-policy: policy precedence (allow wins)"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run web -n "$ns" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/web pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local web_ip=$(kubectl get pod web -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply deny-all first
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
    if kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: Should be blocked initially"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Apply allow policy - in Kubernetes, any allow takes precedence
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client
EOF

    sleep 5

    # Now should be allowed (allow wins over deny)
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: Allow should take precedence"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Policy precedence working (allow wins)"
    return 0
}
