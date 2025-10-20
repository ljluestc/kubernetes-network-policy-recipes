#!/usr/bin/env bash
# Integration test: Cross-namespace communication
# Tests namespace isolation and cross-namespace policies

set -euo pipefail

test_cross_namespace_policy_precedence() {
    local ns1="integration-ns1-$$"
    local ns2="integration-ns2-$$"
    echo "  [TEST] Cross-namespace: namespace selector"

    # Create namespaces with labels
    kubectl create namespace "$ns1" 2>/dev/null || true
    kubectl label namespace "$ns1" environment=production --overwrite 2>/dev/null || true

    kubectl create namespace "$ns2" 2>/dev/null || true
    kubectl label namespace "$ns2" environment=development --overwrite 2>/dev/null || true

    # Deploy pods
    kubectl run web -n "$ns1" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true
    kubectl run client-prod -n "$ns1" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true
    kubectl run client-dev -n "$ns2" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/web -n "$ns1" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    if ! kubectl wait --for=condition=Ready pod/client-prod -n "$ns1" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    if ! kubectl wait --for=condition=Ready pod/client-dev -n "$ns2" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    local web_ip=$(kubectl get pod web -n "$ns1" -o jsonpath='{.status.podIP}')

    # Apply policy: allow from same namespace + specific labeled namespace
    kubectl apply -n "$ns1" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-cross-namespace
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
  - from:
    - namespaceSelector:
        matchLabels:
          environment: development
EOF

    sleep 5

    # Same namespace should work
    if ! kubectl exec client-prod -n "$ns1" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: Same namespace should work"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 1
    fi

    # Labeled namespace should work
    if ! kubectl exec client-dev -n "$ns2" -- timeout 2 wget -q -O- "http://${web_ip}" &>/dev/null; then
        echo "    FAIL: Development namespace should access production"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
    echo "    PASS: Cross-namespace policies working"
    return 0
}

test_namespace_isolation() {
    local ns1="integration-isolated1-$$"
    local ns2="integration-isolated2-$$"
    echo "  [TEST] Cross-namespace: complete isolation"

    kubectl create namespace "$ns1" 2>/dev/null || true
    kubectl create namespace "$ns2" 2>/dev/null || true

    kubectl run app1 -n "$ns1" --image=nginx --labels="app=myapp" --restart=Never 2>/dev/null || true
    kubectl run app2 -n "$ns2" --image=nginx --labels="app=myapp" --restart=Never 2>/dev/null || true
    kubectl run client -n "$ns2" --image=nginx --labels="app=client" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/app1 -n "$ns1" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    if ! kubectl wait --for=condition=Ready pod/app2 pod/client -n "$ns2" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    local app1_ip=$(kubectl get pod app1 -n "$ns1" -o jsonpath='{.status.podIP}')
    local app2_ip=$(kubectl get pod app2 -n "$ns2" -o jsonpath='{.status.podIP}')

    # Apply deny-all in both namespaces
    kubectl apply -n "$ns1" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    kubectl apply -n "$ns2" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    sleep 5

    # Verify cross-namespace blocked
    if kubectl exec client -n "$ns2" -- timeout 2 wget -q -O- "http://${app1_ip}" &>/dev/null; then
        echo "    FAIL: Cross-namespace should be blocked"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 1
    fi

    # Verify same-namespace also blocked (deny-all)
    if kubectl exec client -n "$ns2" -- timeout 2 wget -q -O- "http://${app2_ip}" &>/dev/null; then
        echo "    FAIL: Same namespace should be blocked by deny-all"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
    echo "    PASS: Namespace isolation working"
    return 0
}

test_selective_cross_namespace_access() {
    local ns1="integration-selective1-$$"
    local ns2="integration-selective2-$$"
    echo "  [TEST] Cross-namespace: selective pod access"

    kubectl create namespace "$ns1" 2>/dev/null || true
    kubectl label namespace "$ns1" team=backend --overwrite 2>/dev/null || true

    kubectl create namespace "$ns2" 2>/dev/null || true
    kubectl label namespace "$ns2" team=frontend --overwrite 2>/dev/null || true

    kubectl run api -n "$ns1" --image=nginx --labels="app=api,service=public" --restart=Never 2>/dev/null || true
    kubectl run database -n "$ns1" --image=nginx --labels="app=db,service=private" --restart=Never 2>/dev/null || true
    kubectl run webapp -n "$ns2" --image=nginx --labels="app=web" --restart=Never 2>/dev/null || true

    if ! kubectl wait --for=condition=Ready pod/api pod/database -n "$ns1" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    if ! kubectl wait --for=condition=Ready pod/webapp -n "$ns2" --timeout=60s 2>/dev/null; then
        echo "    SKIP: Pods failed to start"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 0
    fi

    local api_ip=$(kubectl get pod api -n "$ns1" -o jsonpath='{.status.podIP}')
    local db_ip=$(kubectl get pod database -n "$ns1" -o jsonpath='{.status.podIP}')

    # Allow public services from frontend namespace
    kubectl apply -n "$ns1" -f - <<EOF >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-public-services
spec:
  podSelector:
    matchLabels:
      service: public
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: frontend
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-private-services
spec:
  podSelector:
    matchLabels:
      service: private
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

    sleep 5

    # Frontend should access public API
    if ! kubectl exec webapp -n "$ns2" -- timeout 2 wget -q -O- "http://${api_ip}" &>/dev/null; then
        echo "    FAIL: Frontend should access public API"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 1
    fi

    # Frontend should NOT access private database
    if kubectl exec webapp -n "$ns2" -- timeout 2 wget -q -O- "http://${db_ip}" &>/dev/null; then
        echo "    FAIL: Frontend should NOT access private database"
        kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
        return 1
    fi

    kubectl delete namespace "$ns1" "$ns2" --wait=false 2>/dev/null || true
    echo "    PASS: Selective cross-namespace access working"
    return 0
}
