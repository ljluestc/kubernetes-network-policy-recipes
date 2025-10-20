#!/bin/bash
# Cloud Provider Detection Library
# Detects Kubernetes cluster provider and CNI plugin

# Exit on error
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Detect cloud provider
# Returns: gke, eks, aks, kind, minikube, k3s, microk8s, or unknown
detect_cloud_provider() {
    local provider="unknown"

    # Method 1: kubectl cluster-info for API server URL patterns
    local cluster_info=$(kubectl cluster-info 2>/dev/null || echo "")

    # GKE detection via cluster-info
    if echo "$cluster_info" | grep -qi "gke\|googleapis\.com"; then
        provider="gke"
        echo "$provider"
        return 0
    # EKS detection via cluster-info
    elif echo "$cluster_info" | grep -qi "eks\.amazonaws\.com"; then
        provider="eks"
        echo "$provider"
        return 0
    # AKS detection via cluster-info
    elif echo "$cluster_info" | grep -qi "azmk8s\.io"; then
        provider="aks"
        echo "$provider"
        return 0
    fi

    # Method 2: Check kubeconfig context for local clusters
    local context=$(kubectl config current-context 2>/dev/null || echo "")

    if echo "$context" | grep -q "kind-"; then
        provider="kind"
        echo "$provider"
        return 0
    elif echo "$context" | grep -qi "minikube"; then
        provider="minikube"
        echo "$provider"
        return 0
    elif echo "$context" | grep -qi "k3s"; then
        provider="k3s"
        echo "$provider"
        return 0
    fi

    # Method 3: Check for minikube via command
    if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
        provider="minikube"
        echo "$provider"
        return 0
    fi

    # Method 4: Check node labels for cloud providers
    local node_labels=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].metadata.labels // {}' 2>/dev/null || echo "{}")

    # GKE detection via node labels
    if echo "$node_labels" | jq -e 'has("cloud.google.com/gke-nodepool") or has("cloud.google.com/gke-os-distribution")' &>/dev/null; then
        provider="gke"
    # EKS detection via node labels
    elif echo "$node_labels" | jq -e 'has("eks.amazonaws.com/nodegroup") or has("alpha.eksctl.io/cluster-name")' &>/dev/null; then
        provider="eks"
    # AKS detection via node labels
    elif echo "$node_labels" | jq -e 'has("kubernetes.azure.com/cluster") or has("kubernetes.azure.com/role")' &>/dev/null; then
        provider="aks"
    # k3s detection via node labels
    elif echo "$node_labels" | jq -e '.["node.kubernetes.io/instance-type"] == "k3s"' &>/dev/null; then
        provider="k3s"
    # kind detection via node labels
    elif echo "$node_labels" | jq -e 'has("kubernetes.io/hostname") and (.["kubernetes.io/hostname"] | startswith("kind-"))' &>/dev/null; then
        provider="kind"
    fi

    # Method 5: Check provider ID for additional detection
    if [[ "$provider" == "unknown" ]]; then
        local provider_id=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].spec.providerID // ""' 2>/dev/null || echo "")

        if echo "$provider_id" | grep -q "^gce://"; then
            provider="gke"
        elif echo "$provider_id" | grep -q "^aws://"; then
            provider="eks"
        elif echo "$provider_id" | grep -q "^azure://"; then
            provider="aks"
        elif echo "$provider_id" | grep -q "^k3s://"; then
            provider="k3s"
        fi
    fi

    # Method 6: Check for microk8s via snap or node info
    if [[ "$provider" == "unknown" ]]; then
        local node_info=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.nodeInfo.osImage // ""' 2>/dev/null || echo "")
        if echo "$node_info" | grep -qi "microk8s"; then
            provider="microk8s"
        elif command -v snap &>/dev/null && snap list 2>/dev/null | grep -q "microk8s"; then
            provider="microk8s"
        fi
    fi

    # Method 7: Check for control-plane node for local clusters
    if [[ "$provider" == "unknown" ]]; then
        if echo "$node_labels" | jq -e 'has("node-role.kubernetes.io/control-plane") or has("node-role.kubernetes.io/master")' &>/dev/null; then
            # Default to kind for local control-plane clusters
            provider="kind"
        fi
    fi

    echo "$provider"
}

# Detect CNI plugin
# Returns: calico, cilium, weave, flannel, vpc-cni, azure-cni, gcp-cni, kube-router, or unknown
detect_cni_plugin() {
    local cni="unknown"

    # Method 1: Check for CNI DaemonSets and their container images
    # Check for Calico
    if kubectl get daemonset -n kube-system calico-node &>/dev/null; then
        cni="calico"
        echo "$cni"
        return 0
    # Check for Cilium
    elif kubectl get daemonset -n kube-system cilium &>/dev/null || \
         kubectl get daemonset -n kube-system cilium-agent &>/dev/null; then
        cni="cilium"
        echo "$cni"
        return 0
    # Check for Weave
    elif kubectl get daemonset -n kube-system weave-net &>/dev/null; then
        cni="weave"
        echo "$cni"
        return 0
    # Check for Flannel
    elif kubectl get daemonset -n kube-system kube-flannel &>/dev/null || \
         kubectl get daemonset -n kube-system kube-flannel-ds &>/dev/null; then
        cni="flannel"
        echo "$cni"
        return 0
    # Check for AWS VPC CNI
    elif kubectl get daemonset -n kube-system aws-node &>/dev/null; then
        cni="vpc-cni"
        echo "$cni"
        return 0
    # Check for Azure CNI
    elif kubectl get daemonset -n kube-system azure-cni-networkmonitor &>/dev/null || \
         kubectl get daemonset -n kube-system azure-npm &>/dev/null; then
        cni="azure-cni"
        echo "$cni"
        return 0
    # Check for kube-router (used by k3s)
    elif kubectl get daemonset -n kube-system kube-router &>/dev/null; then
        cni="kube-router"
        echo "$cni"
        return 0
    fi

    # Method 2: Check CNI deployments (some CNIs use deployments instead of daemonsets)
    if [[ "$cni" == "unknown" ]]; then
        if kubectl get deployment -n kube-system calico-kube-controllers &>/dev/null; then
            cni="calico"
            echo "$cni"
            return 0
        elif kubectl get deployment -n kube-system cilium-operator &>/dev/null; then
            cni="cilium"
            echo "$cni"
            return 0
        fi
    fi

    # Method 3: Analyze pod network interfaces for CNI-specific patterns
    if [[ "$cni" == "unknown" ]]; then
        # Find a running pod to inspect
        local test_pod=$(kubectl get pods -A -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase=="Running") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -n 1)

        if [[ -n "$test_pod" ]]; then
            local namespace=$(echo "$test_pod" | cut -d'/' -f1)
            local pod_name=$(echo "$test_pod" | cut -d'/' -f2)

            # Get network interface info
            local iface_info=$(kubectl exec -n "$namespace" "$pod_name" -- ip link show 2>/dev/null || echo "")

            if echo "$iface_info" | grep -q "cali[0-9]"; then
                cni="calico"
                echo "$cni"
                return 0
            elif echo "$iface_info" | grep -q "lxc[0-9]\|cilium"; then
                cni="cilium"
                echo "$cni"
                return 0
            elif echo "$iface_info" | grep -q "weave"; then
                cni="weave"
                echo "$cni"
                return 0
            elif echo "$iface_info" | grep -q "veth.*flannel"; then
                cni="flannel"
                echo "$cni"
                return 0
            fi
        fi
    fi

    # Method 4: Check CNI config files in kube-system pods
    if [[ "$cni" == "unknown" ]]; then
        local cni_config=$(kubectl get pods -n kube-system -o json 2>/dev/null | \
            jq -r '.items[].spec.containers[].env[]? | select(.name=="CNI_CONF_NAME") | .value' 2>/dev/null | head -n 1)

        if [[ -n "$cni_config" ]]; then
            if echo "$cni_config" | grep -qi "calico"; then
                cni="calico"
            elif echo "$cni_config" | grep -qi "cilium"; then
                cni="cilium"
            elif echo "$cni_config" | grep -qi "weave"; then
                cni="weave"
            elif echo "$cni_config" | grep -qi "flannel"; then
                cni="flannel"
            fi
        fi
    fi

    # Method 5: Provider-specific CNI detection
    if [[ "$cni" == "unknown" ]]; then
        local provider=$(detect_cloud_provider)

        case "$provider" in
            gke)
                # GKE uses either kubenet (basic) or Calico/Cilium
                # Check if GKE Dataplane V2 (Cilium) is enabled
                if kubectl get nodes -o json 2>/dev/null | \
                   jq -e '.items[0].metadata.labels["cloud.google.com/gke-netd"] == "true"' &>/dev/null; then
                    cni="cilium"
                elif kubectl get nodes -o json 2>/dev/null | \
                     jq -r '.items[0].spec.podCIDR' 2>/dev/null | grep -q "10\."; then
                    cni="gcp-cni"
                fi
                ;;
            eks)
                # EKS defaults to VPC CNI if no other CNI detected
                if kubectl get daemonset -n kube-system aws-node &>/dev/null; then
                    cni="vpc-cni"
                fi
                ;;
            aks)
                # AKS network plugin detection via node labels
                local aks_plugin=$(kubectl get nodes -o json 2>/dev/null | \
                    jq -r '.items[0].metadata.labels["kubernetes.azure.com/network-plugin"] // ""' 2>/dev/null)
                if [[ -n "$aks_plugin" ]]; then
                    cni="azure-cni"
                fi
                ;;
        esac
    fi

    # Method 6: Check for CNI binaries in node filesystem (last resort)
    if [[ "$cni" == "unknown" ]]; then
        local node_name=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].metadata.name' 2>/dev/null)
        if [[ -n "$node_name" ]]; then
            # This requires privileged access and may not work in all environments
            local cni_bin=$(kubectl debug node/"$node_name" -it --image=busybox 2>/dev/null <<< 'ls /opt/cni/bin/ 2>/dev/null' || echo "")
            if echo "$cni_bin" | grep -q "calico"; then
                cni="calico"
            elif echo "$cni_bin" | grep -q "cilium"; then
                cni="cilium"
            fi
        fi
    fi

    echo "$cni"
}

# Get CNI version
get_cni_version() {
    local cni="$1"
    local version="unknown"

    case "$cni" in
        calico)
            version=$(kubectl get deployment -n kube-system calico-kube-controllers -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            # Fallback to daemonset if deployment not found
            if [[ "$version" == "unknown" ]]; then
                version=$(kubectl get daemonset -n kube-system calico-node -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                    grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            fi
            ;;
        cilium)
            version=$(kubectl get daemonset -n kube-system cilium -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            # Fallback to cilium-agent if not found
            if [[ "$version" == "unknown" ]]; then
                version=$(kubectl get daemonset -n kube-system cilium-agent -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                    grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            fi
            ;;
        weave)
            version=$(kubectl get daemonset -n kube-system weave-net -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP '\d+\.\d+\.\d+' || echo "unknown")
            ;;
        flannel)
            version=$(kubectl get daemonset -n kube-system kube-flannel -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            # Fallback to kube-flannel-ds
            if [[ "$version" == "unknown" ]]; then
                version=$(kubectl get daemonset -n kube-system kube-flannel-ds -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                    grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            fi
            ;;
        vpc-cni)
            version=$(kubectl get daemonset -n kube-system aws-node -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            ;;
        azure-cni)
            version=$(kubectl get daemonset -n kube-system azure-npm -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            # Fallback to azure-cni-networkmonitor
            if [[ "$version" == "unknown" ]]; then
                version=$(kubectl get daemonset -n kube-system azure-cni-networkmonitor -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                    grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            fi
            ;;
        kube-router)
            version=$(kubectl get daemonset -n kube-system kube-router -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
                grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
            ;;
        gcp-cni)
            # GCP CNI version is tied to GKE version
            version=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' || echo "unknown")
            ;;
    esac

    echo "$version"
}

# Get Kubernetes version
get_k8s_version() {
    kubectl version --short 2>/dev/null | grep "Server Version" | grep -oP 'v\d+\.\d+\.\d+' || \
    kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' || \
    echo "unknown"
}

# Get cluster region/zone
get_cluster_region() {
    local provider="$1"
    local region="unknown"

    case "$provider" in
        gke)
            region=$(kubectl get nodes -o json 2>/dev/null | \
                jq -r '.items[0].metadata.labels["topology.kubernetes.io/region"] //
                       .items[0].metadata.labels["failure-domain.beta.kubernetes.io/region"] //
                       "unknown"' 2>/dev/null)
            ;;
        eks)
            region=$(kubectl get nodes -o json 2>/dev/null | \
                jq -r '.items[0].metadata.labels["topology.kubernetes.io/region"] //
                       .items[0].metadata.labels["failure-domain.beta.kubernetes.io/region"] //
                       "unknown"' 2>/dev/null)
            ;;
        aks)
            region=$(kubectl get nodes -o json 2>/dev/null | \
                jq -r '.items[0].metadata.labels["topology.kubernetes.io/region"] //
                       .items[0].metadata.labels["failure-domain.beta.kubernetes.io/region"] //
                       "unknown"' 2>/dev/null)
            ;;
        *)
            region="local"
            ;;
    esac

    echo "$region"
}

# Get cluster name
get_cluster_name() {
    local provider="$1"
    local cluster_name="unknown"

    case "$provider" in
        gke)
            cluster_name=$(kubectl config current-context 2>/dev/null | \
                grep -oP 'gke_[^_]+_[^_]+_\K.*' || echo "unknown")
            ;;
        eks)
            cluster_name=$(kubectl config current-context 2>/dev/null | \
                grep -oP '.*@\K.*' || echo "unknown")
            ;;
        aks)
            cluster_name=$(kubectl config current-context 2>/dev/null)
            ;;
        kind)
            cluster_name=$(kubectl config current-context 2>/dev/null | sed 's/kind-//')
            ;;
        *)
            cluster_name=$(kubectl config current-context 2>/dev/null)
            ;;
    esac

    echo "$cluster_name"
}

# Generate comprehensive environment report
generate_environment_report() {
    local provider=$(detect_cloud_provider)
    local cni=$(detect_cni_plugin)
    local cni_version=$(get_cni_version "$cni")
    local k8s_version=$(get_k8s_version)
    local region=$(get_cluster_region "$provider")
    local cluster_name=$(get_cluster_name "$provider")
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    cat <<EOF
{
  "provider": "$provider",
  "cni": {
    "name": "$cni",
    "version": "$cni_version"
  },
  "kubernetes": {
    "version": "$k8s_version"
  },
  "cluster": {
    "name": "$cluster_name",
    "region": "$region",
    "node_count": $node_count
  },
  "detection_timestamp": "$(date -Iseconds)"
}
EOF
}

# Check if NetworkPolicy API is available
check_network_policy_support() {
    if kubectl api-resources | grep -q "networkpolicies.*networking.k8s.io"; then
        echo "true"
    else
        echo "false"
    fi
}

# Main execution when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    case "${1:-}" in
        --provider)
            detect_cloud_provider
            ;;
        --cni)
            detect_cni_plugin
            ;;
        --report)
            generate_environment_report
            ;;
        --json)
            generate_environment_report
            ;;
        *)
            echo "Cloud Provider Detection Utility"
            echo ""
            echo "Usage:"
            echo "  $0 --provider        Detect cloud provider"
            echo "  $0 --cni             Detect CNI plugin"
            echo "  $0 --report          Generate full environment report (JSON)"
            echo "  $0 --json            Alias for --report"
            echo ""
            echo "Or source this script to use functions:"
            echo "  source $0"
            echo "  provider=\$(detect_cloud_provider)"
            echo "  cni=\$(detect_cni_plugin)"
            echo "  report=\$(generate_environment_report)"
            ;;
    esac
fi
