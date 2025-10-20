# Multi-Cloud Environment Support

Comprehensive guide for running Network Policy tests across different cloud providers and CNI plugins.

## Overview

The testing framework automatically detects and adapts to different Kubernetes environments:

- **Cloud Providers**: GKE, EKS, AKS, kind, minikube, k3s, microk8s
- **CNI Plugins**: Calico, Cilium, Weave Net, Flannel, AWS VPC CNI, Azure CNI, GCP CNI
- **Auto-configuration**: Timeout, worker count, and test filtering based on environment

## Quick Start

### Detect Your Environment

```bash
cd test-framework
./parallel-test-runner.sh --detect
```

Output example:
```json
{
  "provider": "kind",
  "cni": {
    "name": "calico",
    "version": "v3.26.1"
  },
  "kubernetes": {
    "version": "v1.28.0"
  },
  "cluster": {
    "name": "np-test",
    "region": "local",
    "node_count": 3
  }
}
```

### Run Tests with Auto-Detection

```bash
# Automatically detects provider and CNI, adjusts settings
./parallel-test-runner.sh

# Skip unsupported recipes for current CNI
./parallel-test-runner.sh --skip-unsupported
```

## Supported Environments

### Google Kubernetes Engine (GKE)

**Detection**: Node labels with `cloud.google.com/gke-nodepool`

**CNI Options**:
- Default: GKE CNI (Kubenet-based)
- Optional: Calico (recommended for NetworkPolicy)
- GKE Dataplane V2: Cilium-based

**Auto-configured Settings**:
- Timeout: 90 seconds
- Workers: 8 parallel

**Example**:
```bash
# Provision GKE cluster with Calico
./provision-cluster.sh --provider gke --name np-test --cni calico --workers 3

# Run tests
./parallel-test-runner.sh
```

**GKE-Specific Features**:
- Dataplane V2 detection
- Cloud logging integration
- Regional cluster support

### Amazon Elastic Kubernetes Service (EKS)

**Detection**: Node labels with `eks.amazonaws.com/nodegroup`

**CNI Options**:
- Default: AWS VPC CNI (requires Calico overlay for NetworkPolicy)
- Recommended: Calico for full NetworkPolicy support

**Auto-configured Settings**:
- Timeout: 90 seconds
- Workers: 8 parallel

**Example**:
```bash
# Provision EKS cluster
./provision-cluster.sh --provider eks --name np-test --cni calico --workers 3

# Run tests
./parallel-test-runner.sh --skip-unsupported
```

**EKS-Specific Features**:
- VPC CNI version detection
- Calico overlay detection
- IAM role integration

**Important**: AWS VPC CNI alone does NOT support NetworkPolicy. Install Calico:
```bash
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml
```

### Azure Kubernetes Service (AKS)

**Detection**: Node labels with `kubernetes.azure.com/cluster`

**CNI Options**:
- Azure CNI (supports NetworkPolicy with Azure Network Policy Manager)
- Kubenet + Calico
- Cilium (preview)

**Auto-configured Settings**:
- Timeout: 90 seconds
- Workers: 8 parallel

**Example**:
```bash
# Provision AKS cluster
./provision-cluster.sh --provider aks --name np-test --workers 3

# Run tests
./parallel-test-runner.sh
```

**AKS-Specific Features**:
- Azure Network Policy Manager detection
- Network plugin detection (azure vs kubenet)
- Azure CNI integration

### kind (Kubernetes in Docker)

**Detection**: Context name starts with `kind-`

**CNI Options**:
- Calico (recommended)
- Cilium
- Weave Net

**Auto-configured Settings**:
- Timeout: 60 seconds
- Workers: 4 parallel

**Example**:
```bash
# Provision kind cluster
./provision-cluster.sh --provider kind --name np-test --cni calico --workers 3

# Run tests
./parallel-test-runner.sh
```

**kind-Specific Features**:
- Fast cluster creation (30-60 seconds)
- Docker-based nodes
- Local development focused

### minikube

**Detection**: minikube command available and running

**CNI Options**:
- Calico
- Cilium
- Weave Net

**Auto-configured Settings**:
- Timeout: 60 seconds
- Workers: 2 parallel

**Example**:
```bash
# Provision minikube cluster
./provision-cluster.sh --provider minikube --name np-test --cni calico

# Run tests
./parallel-test-runner.sh
```

**minikube-Specific Features**:
- Driver detection (docker, virtualbox, kvm2)
- Single-node or multi-node support
- Addon management

### k3s

**Detection**: Node labels with k3s identifier or provider ID `k3s://`

**CNI Options**:
- kube-router (default, supports NetworkPolicy)
- Calico
- Cilium

**Auto-configured Settings**:
- Timeout: 60 seconds
- Workers: 4 parallel

**Example**:
```bash
# Provision k3s cluster
./provision-cluster.sh --provider k3s --cni calico

# Run tests
./parallel-test-runner.sh
```

**k3s-Specific Features**:
- Lightweight distribution
- Edge computing focused
- kube-router NetworkPolicy engine

### microk8s

**Detection**: Node OS image contains "microk8s" or snap packages detected

**CNI Options**:
- Cilium addon (microk8s enable cilium)
- Calico

**Auto-configured Settings**:
- Timeout: 60 seconds
- Workers: 4 parallel

**Example**:
```bash
# Install microk8s and enable Cilium
sudo snap install microk8s --classic
microk8s enable cilium

# Run tests
./parallel-test-runner.sh
```

## CNI Plugin Compatibility

### Calico

**Full NetworkPolicy Support**: ✅

**Features**:
- Ingress/Egress rules
- Namespace selectors
- Pod selectors
- IP blocks (CIDR)
- Port ranges
- Named ports
- SCTP protocol

**Supported Recipes**: All (01-14)

### Cilium

**Full NetworkPolicy Support**: ✅

**Features**:
- All Kubernetes NetworkPolicy features
- Extended with CiliumNetworkPolicy (L7 policies)
- eBPF-based enforcement

**Supported Recipes**: All (01-14)

### Weave Net

**Full NetworkPolicy Support**: ✅

**Features**:
- Most NetworkPolicy features
- SCTP: Partial support

**Supported Recipes**: All (01-14), with SCTP limitations

### Flannel

**NetworkPolicy Support**: ❌

**Note**: Flannel does not support NetworkPolicy natively. Requires Calico overlay.

**Supported Recipes**: None without Calico

### AWS VPC CNI

**NetworkPolicy Support**: ⚠️ Partial (with Calico)

**Features**:
- Requires Calico overlay for NetworkPolicy
- Native VPC networking for pods
- Security groups integration

**Supported Recipes**: All (01-14) with Calico installed

### Azure CNI

**Full NetworkPolicy Support**: ✅ (with Azure NPM)

**Features**:
- Azure Network Policy Manager enforcement
- Native VNet integration

**Supported Recipes**: All (01-14)

## Feature Compatibility Matrix

| Feature | Calico | Cilium | Weave | Flannel | VPC CNI | Azure CNI |
|---------|--------|--------|-------|---------|---------|-----------|
| Ingress Rules | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| Egress Rules | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| Namespace Selectors | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| Pod Selectors | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| IP Blocks (CIDR) | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Port Ranges | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| Named Ports | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |
| SCTP Protocol | ✅ | ✅ | ⚠️ | ❌ | ❌ | ⚠️ |
| Deny-All Policies | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ |

**Legend**:
- ✅ Full support
- ⚠️ Partial support
- ❌ Not supported

## Environment-Specific Configuration

### Automatic Timeout Adjustment

**Cloud Providers** (GKE, EKS, AKS):
- Default: 90 seconds
- Reason: Network latency, cloud API delays

**Local Providers** (kind, minikube, k3s):
- Default: 60 seconds
- Reason: Faster local networking

**Override**:
```bash
./parallel-test-runner.sh -t 120  # Force 120 second timeout
```

### Automatic Worker Adjustment

**Cloud Providers**:
- Default: 8 workers
- Reason: More resources available

**kind, k3s, microk8s**:
- Default: 4 workers
- Reason: Moderate resource usage

**minikube**:
- Default: 2 workers
- Reason: Limited resources

**Override**:
```bash
./parallel-test-runner.sh -w 16  # Force 16 parallel workers
```

## Advanced Usage

### Environment Report

```bash
# Detect provider and CNI
./lib/cloud-detection.sh --report

# Generate compatibility report
./lib/feature-matrix.sh --report

# Get provider-specific config
./lib/provider-config.sh --config
```

### Check Recipe Support

```bash
# Check if recipe 09 is supported
./lib/feature-matrix.sh --check 09 calico

# List supported recipes
./lib/feature-matrix.sh --supported cilium

# List unsupported recipes
./lib/feature-matrix.sh --unsupported flannel
```

### Custom CNI Detection

```bash
# Override CNI detection
export CNI_PLUGIN="calico"
./parallel-test-runner.sh
```

## Cluster Provisioning

### Provision Local Cluster

```bash
# kind with Calico
./provision-cluster.sh --provider kind --name my-test --cni calico --workers 3

# minikube with Cilium
./provision-cluster.sh --provider minikube --cni cilium

# k3s with default CNI
./provision-cluster.sh --provider k3s
```

### Provision Cloud Cluster

```bash
# GKE
export GKE_REGION=us-central1
./provision-cluster.sh --provider gke --name np-test-gke --workers 3

# EKS
export AWS_REGION=us-west-2
./provision-cluster.sh --provider eks --name np-test-eks --workers 3

# AKS
export AKS_LOCATION=eastus
export AKS_RESOURCE_GROUP=np-test-rg
./provision-cluster.sh --provider aks --name np-test-aks --workers 3
```

### Delete Cluster

```bash
# Delete kind cluster
./provision-cluster.sh --delete --provider kind --name my-test

# Delete cloud cluster (saves costs!)
./provision-cluster.sh --delete --provider gke --name np-test-gke
```

## Troubleshooting

### Environment Not Detected

**Symptom**: Shows `provider: unknown` or `cni: unknown`

**Solutions**:
```bash
# Check kubectl access
kubectl get nodes

# Verify node labels
kubectl get nodes -o json | jq '.items[0].metadata.labels'

# Check for CNI DaemonSets
kubectl get daemonset -n kube-system
```

### Tests Failing on Specific Provider

**Symptom**: Tests pass locally but fail on cloud

**Solutions**:
```bash
# Use skip-unsupported flag
./parallel-test-runner.sh --skip-unsupported

# Increase timeout
./parallel-test-runner.sh -t 120

# Check CNI support
./lib/feature-matrix.sh --report
```

### Flannel Not Supporting Policies

**Symptom**: All tests fail with Flannel

**Solution**: Install Calico as overlay:
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/canal.yaml
```

### EKS NetworkPolicy Not Working

**Symptom**: Policies created but not enforced

**Solution**: Install Calico for EKS:
```bash
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml

# Wait for Calico to be ready
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s
```

## Best Practices

### 1. Always Detect First

```bash
./parallel-test-runner.sh --detect
```

### 2. Use Skip-Unsupported for CI/CD

```bash
# In your CI pipeline
./parallel-test-runner.sh --skip-unsupported -j > results.json
```

### 3. Cost Optimization for Cloud

```bash
# Use smaller instance types for testing
export GKE_MACHINE_TYPE=e2-standard-2
export EKS_INSTANCE_TYPE=t3.small
export AKS_VM_SIZE=Standard_B2s

# Delete clusters immediately after testing
trap './provision-cluster.sh --delete --provider gke --name np-test-gke' EXIT
./provision-cluster.sh --provider gke --name np-test-gke
./parallel-test-runner.sh
```

### 4. Multi-Environment Testing

```bash
# Test across all environments
for provider in kind minikube k3s; do
  ./provision-cluster.sh --provider $provider --cni calico
  ./parallel-test-runner.sh -j > results-${provider}.json
  ./provision-cluster.sh --delete --provider $provider
done
```

## Integration with CI/CD

### GitHub Actions

```yaml
- name: Detect Environment
  run: |
    cd test-framework
    ./parallel-test-runner.sh --detect

- name: Run Tests
  run: |
    cd test-framework
    ./parallel-test-runner.sh --skip-unsupported
```

### GitLab CI

```yaml
test:
  script:
    - cd test-framework
    - ./parallel-test-runner.sh --detect
    - ./parallel-test-runner.sh --skip-unsupported
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLOUD_PROVIDER` | Force specific provider | Auto-detected |
| `TEST_TIMEOUT` | Test timeout in seconds | Auto-detected |
| `MAX_WORKERS` | Parallel workers | Auto-detected |
| `CNI_PLUGIN` | Force specific CNI | Auto-detected |
| `ENABLE_CLOUD_LOGGING` | Enable cloud logging | true (cloud), false (local) |

## Architecture

### Detection Flow

```
1. Check kubeconfig context (kind, minikube)
2. Query node labels (cloud providers)
3. Detect CNI DaemonSets (calico-node, cilium, etc.)
4. Apply provider-specific configuration
5. Validate environment
6. Filter unsupported recipes
7. Adjust timeout and workers
8. Run tests
```

### File Structure

```
test-framework/
├── parallel-test-runner.sh          # Main test runner (multi-cloud enabled)
├── provision-cluster.sh              # Cluster provisioning
├── lib/
│   ├── cloud-detection.sh           # Provider and CNI detection
│   ├── feature-matrix.sh            # Feature compatibility
│   └── provider-config.sh           # Provider-specific settings
└── MULTICLOUD.md                    # This documentation
```

## License

Same as parent project.
