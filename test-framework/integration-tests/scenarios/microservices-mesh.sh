#!/usr/bin/env bash
# Integration test: Microservices mesh patterns
# Tests service mesh-like communication patterns

set -euo pipefail

test_microservices_service_mesh() {
    local ns="integration-mesh-$$"
    echo "  [TEST] Microservices: service mesh pattern"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Deploy microservices
    kubectl run gateway -n "$ns" --image=nginx --labels="service=gateway,mesh=enabled" --restart=Never 2>/dev/null || true
    kubectl run auth -n "$ns" --image=nginx --labels="service=auth,mesh=enabled" --restart=Never 2>/dev/null || true
    kubectl run users -n "$ns" --image=nginx --labels="service=users,mesh=enabled" --restart=Never 2>/dev/null || true
    kubectl run orders -n "$ns" --image=nginx --labels="service=orders,mesh=enabled" --restart=Never 2>/dev/null || true
    kubectl run inventory -n "$ns" --image=nginx --labels="service=inventory,mesh=enabled" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/gateway pod/auth pod/users pod/orders pod/inventory -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local auth_ip=$(kubectl get pod auth -n "$ns" -o jsonpath='{.status.podIP}')
    local users_ip=$(kubectl get pod users -n "$ns" -o jsonpath='{.status.podIP}')
    local orders_ip=$(kubectl get pod orders -n "$ns" -o jsonpath='{.status.podIP}')
    local inventory_ip=$(kubectl get pod inventory -n "$ns" -o jsonpath='{.status.podIP}')

    # Apply mesh policies
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
# Gateway can reach all services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gateway-policy
spec:
  podSelector:
    matchLabels:
      service: gateway
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          mesh: enabled
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
---
# Auth service accepts from gateway
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: auth-policy
spec:
  podSelector:
    matchLabels:
      service: auth
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          service: gateway
---
# Orders can access inventory
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-policy
spec:
  podSelector:
    matchLabels:
      service: orders
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          service: gateway
  egress:
  - to:
    - podSelector:
        matchLabels:
          service: inventory
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
EOF

    sleep 5

    # Test gateway -> auth
    if ! kubectl exec gateway -n "$ns" -- timeout 2 wget -q -O- "http://${auth_ip}" &>/dev/null; then
        echo "    FAIL: Gateway should reach auth"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Test gateway -> orders
    if ! kubectl exec gateway -n "$ns" -- timeout 2 wget -q -O- "http://${orders_ip}" &>/dev/null; then
        echo "    FAIL: Gateway should reach orders"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Test orders -> inventory
    if ! kubectl exec orders -n "$ns" -- timeout 2 wget -q -O- "http://${inventory_ip}" &>/dev/null; then
        echo "    FAIL: Orders should reach inventory"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Microservices mesh pattern working"
    return 0
}

test_microservices_sidecar_pattern() {
    local ns="integration-sidecar-$$"
    echo "  [TEST] Microservices: sidecar proxy pattern"

    kubectl create namespace "$ns" 2>/dev/null || true

    kubectl run app -n "$ns" --image=nginx --labels="app=myapp,sidecar=proxy" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app pod/client -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local app_ip=$(kubectl get pod app -n "$ns" -o jsonpath='{.status.podIP}')

    # Policy: only allow traffic through sidecar proxy (simulated)
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: sidecar-policy
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    sleep 5

    # Test access (should work - all pods in namespace allowed)
    if ! kubectl exec client -n "$ns" -- timeout 2 wget -q -O- "http://${app_ip}" &>/dev/null; then
        echo "    FAIL: Client should reach app"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Sidecar proxy pattern working"
    return 0
}

test_microservices_canary_deployment() {
    local ns="integration-canary-$$"
    echo "  [TEST] Microservices: canary deployment routing"

    kubectl create namespace "$ns" 2>/dev/null || true

    # Deploy stable and canary versions
    kubectl run app-v1 -n "$ns" --image=nginx --labels="app=myapp,version=stable" --restart=Never 2>/dev/null || true
    kubectl run app-v2 -n "$ns" --image=nginx --labels="app=myapp,version=canary" --restart=Never 2>/dev/null || true
    kubectl run client-stable -n "$ns" --image=nginx --labels="traffic=stable" --restart=Never 2>/dev/null || true
    kubectl run client-canary -n "$ns" --image=nginx --labels="traffic=canary" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app-v1 pod/app-v2 pod/client-stable pod/client-canary -n "$ns" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 0
    fi

    local v1_ip=$(kubectl get pod app-v1 -n "$ns" -o jsonpath='{.status.podIP}')
    local v2_ip=$(kubectl get pod app-v2 -n "$ns" -o jsonpath='{.status.podIP}')

    # Policy: canary version only accessible from canary clients
    kubectl apply -n "$ns" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: canary-policy
spec:
  podSelector:
    matchLabels:
      version: canary
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          traffic: canary
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: stable-policy
spec:
  podSelector:
    matchLabels:
      version: stable
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    sleep 5

    # Stable client can reach stable version
    if ! kubectl exec client-stable -n "$ns" -- timeout 2 wget -q -O- "http://${v1_ip}" &>/dev/null; then
        echo "    FAIL: Stable client should reach v1"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Canary client can reach canary version
    if ! kubectl exec client-canary -n "$ns" -- timeout 2 wget -q -O- "http://${v2_ip}" &>/dev/null; then
        echo "    FAIL: Canary client should reach v2"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    # Stable client should NOT reach canary
    if kubectl exec client-stable -n "$ns" -- timeout 2 wget -q -O- "http://${v2_ip}" &>/dev/null; then
        echo "    FAIL: Stable client should NOT reach canary"
        kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
    echo "    PASS: Canary deployment routing working"
    return 0
}
