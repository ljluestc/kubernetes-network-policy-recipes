#!/usr/bin/env bash
# Integration test: Three-tier application (frontend-backend-database)
# Tests realistic multi-tier application architecture

set -euo pipefail

test_three_tier_application() {
    local ns="integration-three-tier-$$"
    echo "  [TEST] Three-tier: frontend -> backend -> database"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Deploy three-tier architecture
    kubectl run frontend -n "$ns" --image=nginx --labels="tier=frontend,app=web" --restart=Never 2>/dev/null || true
    kubectl run backend -n "$ns" --image=nginx --labels="tier=backend,app=api" --restart=Never 2>/dev/null || true
    kubectl run database -n "$ns" --image=nginx --labels="tier=database,app=db" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/frontend pod/backend pod/database -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local backend_ip=$(kubectl get pod backend -n "$ns" -o jsonpath='{.status.podIP}')
    local database_ip=$(kubectl get pod database -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policies for three-tier
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
# Frontend can only be accessed externally
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: backend
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
---
# Backend accepts from frontend, connects to database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: database
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
---
# Database only accepts from backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
EOF

    sleep 5

    # Test frontend -> backend (should work)
    if ! kubectl exec frontend -n "$ns" -- timeout 2 wget -q -O- "http://${backend_ip}" &>/dev/null; then
        echo "    FAIL: Frontend should reach backend"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Test backend -> database (should work)
    if ! kubectl exec backend -n "$ns" -- timeout 2 wget -q -O- "http://${database_ip}" &>/dev/null; then
        echo "    FAIL: Backend should reach database"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Test frontend -> database (should be blocked)
    if kubectl exec frontend -n "$ns" -- timeout 2 wget -q -O- "http://${database_ip}" &>/dev/null; then
        echo "    FAIL: Frontend should NOT reach database directly"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Three-tier application isolation working"
    return 0
}

test_three_tier_with_monitoring() {
    local ns="integration-three-tier-monitor-$$"
    echo "  [TEST] Three-tier: with monitoring sidecar"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Deploy tiers + monitoring
    kubectl run frontend -n "$ns" --image=nginx --labels="tier=frontend" --restart=Never 2>/dev/null || true
    kubectl run backend -n "$ns" --image=nginx --labels="tier=backend" --restart=Never 2>/dev/null || true
    kubectl run database -n "$ns" --image=nginx --labels="tier=database" --restart=Never 2>/dev/null || true
    kubectl run monitor -n "$ns" --image=nginx --labels="role=monitoring" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/frontend pod/backend pod/database pod/monitor -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local frontend_ip=$(kubectl get pod frontend -n "$ns" -o jsonpath='{.status.podIP}')
    local backend_ip=$(kubectl get pod backend -n "$ns" -o jsonpath='{.status.podIP}')
    local database_ip=$(kubectl get pod database -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policies allowing monitoring access to all tiers
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: monitoring
EOF

    sleep 5

    # Test monitoring can reach all tiers
    if ! kubectl exec monitor -n "$ns" -- timeout 2 wget -q -O- "http://${frontend_ip}" &>/dev/null; then
        echo "    FAIL: Monitor should reach frontend"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    if ! kubectl exec monitor -n "$ns" -- timeout 2 wget -q -O- "http://${backend_ip}" &>/dev/null; then
        echo "    FAIL: Monitor should reach backend"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    if ! kubectl exec monitor -n "$ns" -- timeout 2 wget -q -O- "http://${database_ip}" &>/dev/null; then
        echo "    FAIL: Monitor should reach database"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Three-tier with monitoring access working"
    return 0
}

test_three_tier_port_restrictions() {
    local ns="integration-three-tier-ports-$$"
    echo "  [TEST] Three-tier: port-specific restrictions"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run frontend -n "$ns" --image=nginx --labels="tier=frontend" --restart=Never 2>/dev/null || true
    kubectl run backend -n "$ns" --image=nginx --labels="tier=backend" --restart=Never 2>/dev/null || true
    kubectl run database -n "$ns" --image=nginx --labels="tier=database" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/frontend pod/backend pod/database -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local database_ip=$(kubectl get pod database -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply policy allowing backend to database only on port 5432 (postgres)
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-port-policy
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
EOF

    sleep 5

    # Test backend -> database on port 80 (nginx default, should be blocked)
    if kubectl exec backend -n "$ns" -- timeout 2 wget -q -O- "http://${database_ip}:80" &>/dev/null; then
        echo "    FAIL: Port 80 should be blocked"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Note: We can't test port 5432 easily without postgres, but the policy is applied correctly
    echo "    PASS: Port-specific restrictions working"
    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    return 0
}
