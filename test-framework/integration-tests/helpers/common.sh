#!/usr/bin/env bash
# Common helper functions for integration tests

# Wait for pod to be ready with custom timeout
wait_for_pod_ready() {
    local pod_name="$1"
    local namespace="$2"
    local timeout="${3:-60}"

    if kubectl wait --for=condition=Ready "pod/${pod_name}" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get pod IP address
get_pod_ip() {
    local pod_name="$1"
    local namespace="$2"

    kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.podIP}' 2>/dev/null || echo ""
}

# Test connectivity between pods
test_connectivity() {
    local source_pod="$1"
    local source_ns="$2"
    local target_ip="$3"
    local timeout="${4:-2}"

    kubectl exec "$source_pod" -n "$source_ns" -- timeout "$timeout" wget -q -O- "http://${target_ip}" &>/dev/null
}

# Apply network policy with error handling
apply_network_policy() {
    local namespace="$1"
    local policy_yaml="$2"

    echo "$policy_yaml" | kubectl apply -n "$namespace" -f - &>/dev/null
}

# Clean up namespace
cleanup_namespace() {
    local namespace="$1"
    kubectl delete namespace "$namespace" --wait=false 2>/dev/null || true
}

# Create test pods with labels
create_test_pod() {
    local name="$1"
    local namespace="$2"
    local labels="$3"

    kubectl run "$name" -n "$namespace" --image=nginx --labels="$labels" --restart=Never 2>/dev/null || true
}

# Wait for multiple pods
wait_for_pods() {
    local namespace="$1"
    shift
    local pod_names=("$@")

    local all_ready=true
    for pod in "${pod_names[@]}"; do
        if ! wait_for_pod_ready "$pod" "$namespace" 60; then
            all_ready=false
        fi
    done

    [[ "$all_ready" == "true" ]]
}

# Get CNI plugin name
get_cni_plugin() {
    # Try to detect CNI from running pods
    if kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null; then
        echo "cilium"
    elif kubectl get pods -n kube-system -l k8s-app=calico-node &>/dev/null; then
        echo "calico"
    elif kubectl get pods -n kube-system -l component=kube-proxy &>/dev/null; then
        echo "kubenet"
    else
        echo "unknown"
    fi
}

# Verify network policy support
verify_network_policy_support() {
    local test_ns="netpol-verify-$$"
    kubectl create namespace "$test_ns" 2>/dev/null || return 1

    local result=0
    if kubectl apply -n "$test_ns" -f - <<EOF &>/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-policy
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
    then
        result=0
    else
        result=1
    fi

    kubectl delete namespace "$test_ns" --wait=false 2>/dev/null || true
    return $result
}
