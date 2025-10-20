#!/bin/bash
# Provider-Specific Configuration
# Handles environment-specific settings and optimizations

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/cloud-detection.sh" ]]; then
    source "$SCRIPT_DIR/cloud-detection.sh"
fi
if [[ -f "$SCRIPT_DIR/feature-matrix.sh" ]]; then
    source "$SCRIPT_DIR/feature-matrix.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Apply provider-specific configurations
apply_provider_config() {
    local provider="${1:-$(detect_cloud_provider)}"

    case "$provider" in
        gke)
            apply_gke_config
            ;;
        eks)
            apply_eks_config
            ;;
        aks)
            apply_aks_config
            ;;
        kind)
            apply_kind_config
            ;;
        minikube)
            apply_minikube_config
            ;;
        k3s)
            apply_k3s_config
            ;;
        microk8s)
            apply_microk8s_config
            ;;
        *)
            warn "Unknown provider: $provider, using defaults"
            ;;
    esac
}

# GKE-specific configuration
apply_gke_config() {
    info "Applying GKE-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="gke"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-90}"
    export MAX_WORKERS="${MAX_WORKERS:-8}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-true}"

    # GKE-specific network policy considerations
    export GKE_DATAPLANE_V2="${GKE_DATAPLANE_V2:-false}"

    # Check if GKE Dataplane V2 (Cilium) is enabled
    if kubectl get nodes -o json 2>/dev/null | jq -e '.items[0].metadata.labels["cloud.google.com/gke-netd"] == "true"' &>/dev/null; then
        export GKE_DATAPLANE_V2="true"
        info "GKE Dataplane V2 (Cilium) detected"
    fi
}

# EKS-specific configuration
apply_eks_config() {
    info "Applying EKS-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="eks"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-90}"
    export MAX_WORKERS="${MAX_WORKERS:-8}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-true}"

    # EKS-specific settings
    export AWS_VPC_CNI_VERSION=$(kubectl get daemonset -n kube-system aws-node -o json 2>/dev/null | \
        jq -r '.spec.template.spec.containers[0].image' 2>/dev/null | \
        grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")

    info "AWS VPC CNI version: $AWS_VPC_CNI_VERSION"

    # Check if Network Policy support is enabled (requires Calico)
    if kubectl get daemonset -n kube-system calico-node &>/dev/null; then
        export EKS_NETWORK_POLICY_ENABLED="true"
        info "EKS Network Policy (Calico) is enabled"
    else
        export EKS_NETWORK_POLICY_ENABLED="false"
        warn "EKS Network Policy not detected. Install Calico for full NetworkPolicy support."
    fi
}

# AKS-specific configuration
apply_aks_config() {
    info "Applying AKS-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="aks"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-90}"
    export MAX_WORKERS="${MAX_WORKERS:-8}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-true}"

    # AKS-specific settings
    local aks_network_plugin=$(kubectl get nodes -o json 2>/dev/null | \
        jq -r '.items[0].metadata.labels["kubernetes.azure.com/network-plugin"] // "unknown"' 2>/dev/null)

    export AKS_NETWORK_PLUGIN="$aks_network_plugin"
    info "AKS Network Plugin: $AKS_NETWORK_PLUGIN"

    # Check for Azure Network Policy Manager
    if kubectl get daemonset -n kube-system azure-npm &>/dev/null; then
        export AKS_NPM_ENABLED="true"
        info "Azure Network Policy Manager is enabled"
    else
        export AKS_NPM_ENABLED="false"
    fi
}

# kind-specific configuration
apply_kind_config() {
    info "Applying kind-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="kind"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
    export MAX_WORKERS="${MAX_WORKERS:-4}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-false}"

    # kind-specific settings
    export KIND_CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | sed 's/kind-//')
    info "kind cluster: $KIND_CLUSTER_NAME"
}

# minikube-specific configuration
apply_minikube_config() {
    info "Applying minikube-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="minikube"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
    export MAX_WORKERS="${MAX_WORKERS:-2}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-false}"

    # minikube-specific settings
    local minikube_driver=$(minikube profile list -o json 2>/dev/null | \
        jq -r '.valid[0].Config.Driver // "unknown"' 2>/dev/null || echo "unknown")

    export MINIKUBE_DRIVER="$minikube_driver"
    info "minikube driver: $MINIKUBE_DRIVER"
}

# k3s-specific configuration
apply_k3s_config() {
    info "Applying k3s-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="k3s"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
    export MAX_WORKERS="${MAX_WORKERS:-4}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-false}"

    # k3s uses kube-router or Calico for NetworkPolicy
    if kubectl get daemonset -n kube-system kube-router &>/dev/null; then
        export K3S_NETWORK_POLICY_ENGINE="kube-router"
    elif kubectl get daemonset -n kube-system calico-node &>/dev/null; then
        export K3S_NETWORK_POLICY_ENGINE="calico"
    else
        export K3S_NETWORK_POLICY_ENGINE="unknown"
    fi

    info "k3s Network Policy engine: $K3S_NETWORK_POLICY_ENGINE"
}

# microk8s-specific configuration
apply_microk8s_config() {
    info "Applying microk8s-specific configuration..."

    # Set environment variables
    export CLOUD_PROVIDER="microk8s"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
    export MAX_WORKERS="${MAX_WORKERS:-4}"
    export ENABLE_CLOUD_LOGGING="${ENABLE_CLOUD_LOGGING:-false}"

    # Check if Cilium addon is enabled
    if microk8s status 2>/dev/null | grep -q "cilium: enabled"; then
        export MICROK8S_CILIUM_ENABLED="true"
        info "microk8s Cilium addon is enabled"
    else
        export MICROK8S_CILIUM_ENABLED="false"
    fi
}

# Get environment-adjusted timeout
get_adjusted_timeout() {
    local base_timeout="${1:-60}"
    local provider="${2:-$(detect_cloud_provider)}"

    local recommended=$(get_provider_timeout "$provider")

    # Use the larger of base_timeout and recommended
    if [[ $base_timeout -lt $recommended ]]; then
        echo "$recommended"
    else
        echo "$base_timeout"
    fi
}

# Get environment-adjusted workers
get_adjusted_workers() {
    local base_workers="${1:-4}"
    local provider="${2:-$(detect_cloud_provider)}"

    local recommended=$(get_provider_workers "$provider")

    # Use the larger of base_workers and recommended
    if [[ $base_workers -lt $recommended ]]; then
        echo "$recommended"
    else
        echo "$base_workers"
    fi
}

# Validate environment is ready for testing
validate_environment() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"

    info "Validating environment for testing..."

    # Check kubectl access
    if ! kubectl get nodes &>/dev/null; then
        error "Cannot access Kubernetes cluster. Check kubectl configuration."
        return 1
    fi

    # Check NetworkPolicy API
    if ! kubectl api-resources | grep -q "networkpolicies.*networking.k8s.io"; then
        error "NetworkPolicy API not available in this cluster"
        return 1
    fi

    # CNI-specific validation
    case "$cni" in
        flannel)
            warn "Flannel does not support NetworkPolicy natively"
            warn "Consider installing Calico for NetworkPolicy support"
            return 1
            ;;
        vpc-cni)
            if [[ "$provider" == "eks" ]]; then
                if [[ "${EKS_NETWORK_POLICY_ENABLED:-false}" != "true" ]]; then
                    warn "EKS detected with VPC CNI but no NetworkPolicy support"
                    warn "Install Calico for NetworkPolicy: https://docs.aws.amazon.com/eks/latest/userguide/calico.html"
                    return 1
                fi
            fi
            ;;
    esac

    info "Environment validation passed"
    return 0
}

# Generate provider-specific test configuration
generate_test_config() {
    local provider="${1:-$(detect_cloud_provider)}"
    local cni="${2:-$(detect_cni_plugin)}"

    local timeout=$(get_provider_timeout "$provider")
    local workers=$(get_provider_workers "$provider")
    local supported=($(get_supported_recipes "$cni"))

    cat <<EOF
{
  "provider": "$provider",
  "cni": "$cni",
  "test_config": {
    "timeout_seconds": $timeout,
    "parallel_workers": $workers,
    "supported_recipes": $(printf '%s\n' "${supported[@]}" | jq -R . | jq -s .)
  },
  "environment_variables": {
    "CLOUD_PROVIDER": "$provider",
    "TEST_TIMEOUT": "$timeout",
    "MAX_WORKERS": "$workers"
  },
  "generated_at": "$(date -Iseconds)"
}
EOF
}

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --apply)
            provider="${2:-$(detect_cloud_provider)}"
            apply_provider_config "$provider"
            ;;
        --validate)
            provider="${2:-$(detect_cloud_provider)}"
            cni="${3:-$(detect_cni_plugin)}"
            validate_environment "$provider" "$cni"
            ;;
        --config)
            generate_test_config
            ;;
        *)
            echo "Provider Configuration Utility"
            echo ""
            echo "Usage:"
            echo "  $0 --apply [provider]       Apply provider-specific configuration"
            echo "  $0 --validate [provider] [cni]  Validate environment"
            echo "  $0 --config                 Generate test configuration (JSON)"
            echo ""
            echo "Or source this script to use functions:"
            echo "  source $0"
            echo "  apply_provider_config"
            echo "  validate_environment"
            ;;
    esac
fi
