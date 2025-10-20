#!/bin/bash
# Cluster Provisioning Script
# Provisions Kubernetes clusters across different providers for testing

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Default configuration
CLUSTER_NAME="${CLUSTER_NAME:-np-test}"
PROVIDER="${PROVIDER:-kind}"
K8S_VERSION="${K8S_VERSION:-1.28}"
NODE_COUNT="${NODE_COUNT:-3}"
INSTALL_CNI="${INSTALL_CNI:-calico}"

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Provision Kubernetes clusters for Network Policy testing

OPTIONS:
    -p, --provider PROVIDER    Cloud provider (kind, minikube, k3s, gke, eks, aks)
    -n, --name NAME            Cluster name (default: np-test)
    -v, --version VERSION      Kubernetes version (default: 1.28)
    -c, --cni CNI              CNI plugin (calico, cilium, weave, none)
    -w, --workers NUM          Number of worker nodes (default: 3)
    --delete                   Delete cluster instead of creating
    -h, --help                 Show this help message

EXAMPLES:
    $0 --provider kind --cni calico
    $0 --provider minikube --version 1.27
    $0 --provider gke --name my-test-cluster --workers 5
    $0 --delete --provider kind --name np-test

SUPPORTED PROVIDERS:
    kind       - Local Kubernetes cluster (Docker)
    minikube   - Local Kubernetes cluster (VM or Docker)
    k3s        - Lightweight Kubernetes distribution
    gke        - Google Kubernetes Engine
    eks        - Amazon Elastic Kubernetes Service
    aks        - Azure Kubernetes Service

SUPPORTED CNI PLUGINS:
    calico     - Project Calico (recommended)
    cilium     - Cilium
    weave      - Weave Net
    none       - Use provider default

EOF
    exit 1
}

# Create kind cluster
create_kind_cluster() {
    log "Creating kind cluster: $CLUSTER_NAME"

    # Check if kind is installed
    if ! command -v kind &>/dev/null; then
        error "kind not installed. Install with: curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/"
        exit 1
    fi

    # Create kind config
    local kind_config="/tmp/kind-${CLUSTER_NAME}.yaml"
    cat > "$kind_config" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER_NAME
nodes:
- role: control-plane
$(for i in $(seq 1 $NODE_COUNT); do echo "- role: worker"; done)
networking:
  disableDefaultCNI: $([ "$INSTALL_CNI" != "none" ] && echo "true" || echo "false")
  podSubnet: "10.244.0.0/16"
EOF

    # Create cluster
    kind create cluster --config "$kind_config" --image "kindest/node:v${K8S_VERSION}.0" || {
        error "Failed to create kind cluster"
        exit 1
    }

    # Install CNI
    if [[ "$INSTALL_CNI" != "none" ]]; then
        install_cni_kind "$INSTALL_CNI"
    fi

    success "kind cluster created: $CLUSTER_NAME"
}

# Delete kind cluster
delete_kind_cluster() {
    log "Deleting kind cluster: $CLUSTER_NAME"
    kind delete cluster --name "$CLUSTER_NAME" || {
        error "Failed to delete kind cluster"
        exit 1
    }
    success "kind cluster deleted: $CLUSTER_NAME"
}

# Create minikube cluster
create_minikube_cluster() {
    log "Creating minikube cluster: $CLUSTER_NAME"

    # Check if minikube is installed
    if ! command -v minikube &>/dev/null; then
        error "minikube not installed. Install from: https://minikube.sigs.k8s.io/docs/start/"
        exit 1
    fi

    # Create cluster
    minikube start \
        --profile="$CLUSTER_NAME" \
        --kubernetes-version="v${K8S_VERSION}.0" \
        --nodes="$((NODE_COUNT + 1))" \
        --cni="${INSTALL_CNI}" \
        --network-plugin=cni || {
        error "Failed to create minikube cluster"
        exit 1
    }

    success "minikube cluster created: $CLUSTER_NAME"
}

# Delete minikube cluster
delete_minikube_cluster() {
    log "Deleting minikube cluster: $CLUSTER_NAME"
    minikube delete --profile="$CLUSTER_NAME" || {
        error "Failed to delete minikube cluster"
        exit 1
    }
    success "minikube cluster deleted: $CLUSTER_NAME"
}

# Create k3s cluster
create_k3s_cluster() {
    log "Creating k3s cluster..."
    warn "k3s installation requires root privileges"

    # Install k3s
    curl -sfL https://get.k3s.io | sh -s - \
        --cluster-init \
        --flannel-backend=none \
        --disable-network-policy || {
        error "Failed to install k3s"
        exit 1
    }

    # Wait for k3s to be ready
    sleep 10

    # Copy kubeconfig
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config

    # Install CNI
    if [[ "$INSTALL_CNI" != "none" ]]; then
        install_cni_generic "$INSTALL_CNI"
    fi

    success "k3s cluster created"
}

# Delete k3s cluster
delete_k3s_cluster() {
    log "Deleting k3s cluster..."
    sudo /usr/local/bin/k3s-uninstall.sh || {
        error "Failed to delete k3s cluster"
        exit 1
    }
    success "k3s cluster deleted"
}

# Install CNI on kind
install_cni_kind() {
    local cni="$1"
    log "Installing CNI: $cni"

    case "$cni" in
        calico)
            kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
            ;;
        cilium)
            kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.14.0/install/kubernetes/quick-install.yaml
            ;;
        weave)
            kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
            ;;
        *)
            warn "Unknown CNI: $cni"
            return 1
            ;;
    esac

    # Wait for CNI to be ready
    log "Waiting for CNI to be ready..."
    kubectl wait --for=condition=ready --timeout=300s -n kube-system pods --all

    success "CNI $cni installed"
}

# Install CNI (generic)
install_cni_generic() {
    local cni="$1"
    install_cni_kind "$cni"
}

# Create GKE cluster
create_gke_cluster() {
    log "Creating GKE cluster: $CLUSTER_NAME"

    # Check if gcloud is installed
    if ! command -v gcloud &>/dev/null; then
        error "gcloud not installed. Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    local machine_type="${GKE_MACHINE_TYPE:-e2-standard-4}"
    local region="${GKE_REGION:-us-central1}"

    # Create cluster
    gcloud container clusters create "$CLUSTER_NAME" \
        --cluster-version="${K8S_VERSION}" \
        --machine-type="$machine_type" \
        --num-nodes="$NODE_COUNT" \
        --region="$region" \
        --enable-network-policy \
        --enable-ip-alias || {
        error "Failed to create GKE cluster"
        exit 1
    }

    # Get credentials
    gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$region"

    success "GKE cluster created: $CLUSTER_NAME"
    warn "Remember to delete the cluster to avoid charges: $0 --delete --provider gke --name $CLUSTER_NAME"
}

# Delete GKE cluster
delete_gke_cluster() {
    log "Deleting GKE cluster: $CLUSTER_NAME"

    local region="${GKE_REGION:-us-central1}"

    gcloud container clusters delete "$CLUSTER_NAME" \
        --region="$region" \
        --quiet || {
        error "Failed to delete GKE cluster"
        exit 1
    }

    success "GKE cluster deleted: $CLUSTER_NAME"
}

# Create EKS cluster
create_eks_cluster() {
    log "Creating EKS cluster: $CLUSTER_NAME"

    # Check if eksctl is installed
    if ! command -v eksctl &>/dev/null; then
        error "eksctl not installed. Install from: https://eksctl.io/"
        exit 1
    fi

    local region="${AWS_REGION:-us-west-2}"
    local instance_type="${EKS_INSTANCE_TYPE:-t3.medium}"

    # Create cluster
    eksctl create cluster \
        --name="$CLUSTER_NAME" \
        --version="${K8S_VERSION}" \
        --region="$region" \
        --nodes="$NODE_COUNT" \
        --node-type="$instance_type" || {
        error "Failed to create EKS cluster"
        exit 1
    }

    # Install Calico for NetworkPolicy support
    if [[ "$INSTALL_CNI" == "calico" ]] || [[ "$INSTALL_CNI" == "none" ]]; then
        log "Installing Calico for NetworkPolicy support..."
        kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
        kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml
    fi

    success "EKS cluster created: $CLUSTER_NAME"
    warn "Remember to delete the cluster to avoid charges: $0 --delete --provider eks --name $CLUSTER_NAME"
}

# Delete EKS cluster
delete_eks_cluster() {
    log "Deleting EKS cluster: $CLUSTER_NAME"

    local region="${AWS_REGION:-us-west-2}"

    eksctl delete cluster \
        --name="$CLUSTER_NAME" \
        --region="$region" || {
        error "Failed to delete EKS cluster"
        exit 1
    }

    success "EKS cluster deleted: $CLUSTER_NAME"
}

# Create AKS cluster
create_aks_cluster() {
    log "Creating AKS cluster: $CLUSTER_NAME"

    # Check if az is installed
    if ! command -v az &>/dev/null; then
        error "Azure CLI not installed. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    local resource_group="${AKS_RESOURCE_GROUP:-np-test-rg}"
    local location="${AKS_LOCATION:-eastus}"
    local vm_size="${AKS_VM_SIZE:-Standard_DS2_v2}"

    # Create resource group
    az group create --name="$resource_group" --location="$location"

    # Create cluster
    az aks create \
        --resource-group="$resource_group" \
        --name="$CLUSTER_NAME" \
        --kubernetes-version="${K8S_VERSION}" \
        --node-count="$NODE_COUNT" \
        --node-vm-size="$vm_size" \
        --network-plugin=azure \
        --network-policy=calico || {
        error "Failed to create AKS cluster"
        exit 1
    }

    # Get credentials
    az aks get-credentials --resource-group="$resource_group" --name="$CLUSTER_NAME"

    success "AKS cluster created: $CLUSTER_NAME"
    warn "Remember to delete the cluster to avoid charges: $0 --delete --provider aks --name $CLUSTER_NAME"
}

# Delete AKS cluster
delete_aks_cluster() {
    log "Deleting AKS cluster: $CLUSTER_NAME"

    local resource_group="${AKS_RESOURCE_GROUP:-np-test-rg}"

    az aks delete \
        --resource-group="$resource_group" \
        --name="$CLUSTER_NAME" \
        --yes || {
        error "Failed to delete AKS cluster"
        exit 1
    }

    # Delete resource group
    az group delete --name="$resource_group" --yes

    success "AKS cluster deleted: $CLUSTER_NAME"
}

# Main execution
main() {
    local delete_cluster=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--provider) PROVIDER="$2"; shift 2 ;;
            -n|--name) CLUSTER_NAME="$2"; shift 2 ;;
            -v|--version) K8S_VERSION="$2"; shift 2 ;;
            -c|--cni) INSTALL_CNI="$2"; shift 2 ;;
            -w|--workers) NODE_COUNT="$2"; shift 2 ;;
            --delete) delete_cluster=true; shift ;;
            -h|--help) usage ;;
            *) error "Unknown option: $1"; usage ;;
        esac
    done

    # Execute based on provider
    if [[ "$delete_cluster" == "true" ]]; then
        case "$PROVIDER" in
            kind) delete_kind_cluster ;;
            minikube) delete_minikube_cluster ;;
            k3s) delete_k3s_cluster ;;
            gke) delete_gke_cluster ;;
            eks) delete_eks_cluster ;;
            aks) delete_aks_cluster ;;
            *) error "Unknown provider: $PROVIDER"; usage ;;
        esac
    else
        case "$PROVIDER" in
            kind) create_kind_cluster ;;
            minikube) create_minikube_cluster ;;
            k3s) create_k3s_cluster ;;
            gke) create_gke_cluster ;;
            eks) create_eks_cluster ;;
            aks) create_aks_cluster ;;
            *) error "Unknown provider: $PROVIDER"; usage ;;
        esac
    fi
}

main "$@"
