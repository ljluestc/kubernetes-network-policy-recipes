# Network Policy Recipes - Automation Guide

Comprehensive automation tools for deploying, testing, and validating Kubernetes Network Policy recipes.

## Overview

This guide provides automation scripts to streamline working with the 15 network policy recipes in this repository.

## Available Scripts

### 1. Deploy All Policies (`deploy-all-policies.sh`)

Deploys all network policies in sequence with validation.

**Features:**
- Sequential deployment of all 15 recipes
- YAML extraction from markdown files
- Dry-run mode for validation
- Customizable namespace and wait times
- Deployment summary and verification

**Usage:**
```bash
# Deploy all policies to default namespace
./deploy-all-policies.sh

# Deploy to specific namespace
./deploy-all-policies.sh --namespace production

# Dry-run to validate without applying
./deploy-all-policies.sh --dry-run

# Custom wait time between deployments
./deploy-all-policies.sh --wait 10
```

**Options:**
- `-n, --namespace` - Target namespace (default: default)
- `-w, --wait` - Wait time in seconds between deployments (default: 5)
- `-d, --dry-run` - Validate without applying
- `-h, --help` - Show help message

### 2. Test All Policies (`test-all-policies.sh`)

Comprehensive test suite to verify network policies work as expected.

**Features:**
- Automated test environment setup
- Tests for deny-all, allow-specific, port-based, and egress policies
- Pod-to-pod connectivity verification
- Automatic cleanup
- Test result summary

**Usage:**
```bash
# Run all tests in default namespace
./test-all-policies.sh

# Run tests in custom namespace
./test-all-policies.sh --namespace test-policies

# Verbose mode
./test-all-policies.sh --verbose
```

**Tests Included:**
- ✓ NP-01: Deny all traffic to application
- ✓ NP-02: Limit traffic to application (allow from specific pods)
- ✓ NP-09: Allow traffic only to specific port
- ✓ NP-11: Deny egress traffic from application

**Options:**
- `-n, --namespace` - Test namespace (default: policy-demo)
- `-t, --timeout` - Test timeout in seconds (default: 30)
- `-v, --verbose` - Enable verbose output
- `-h, --help` - Show help message

### 3. Validate Recipes (`validate-recipes.sh`)

Validation suite to check completeness and consistency of recipe files.

**Features:**
- Checks for required sections (Overview, Objectives, etc.)
- Validates YAML frontmatter
- Validates NetworkPolicy YAML syntax
- Verifies presence of test commands
- Comprehensive validation report

**Usage:**
```bash
# Validate all recipe files
./validate-recipes.sh
```

**Checks Performed:**
- ✓ YAML frontmatter presence and completeness
- ✓ Required sections (Overview, Objectives, Background, Requirements, Acceptance Criteria)
- ✓ NetworkPolicy YAML syntax validation
- ✓ Test/demo command presence

## Recipe Inventory

### Complete Recipe List (15 recipes)

| ID | File | Description | Category |
|----|------|-------------|----------|
| NP-00 | 00-create-cluster.md | Create Kubernetes Cluster | Setup |
| NP-01 | 01-deny-all-traffic-to-an-application.md | Deny All Traffic | Basics |
| NP-02 | 02-limit-traffic-to-an-application.md | Limit Traffic to Application | Basics |
| NP-02A | 02a-allow-all-traffic-to-an-application.md | Allow All Traffic | Basics |
| NP-03 | 03-deny-all-non-whitelisted-traffic-in-the-namespace.md | Deny Non-Whitelisted Traffic | Namespace |
| NP-04 | 04-deny-traffic-from-other-namespaces.md | Deny Traffic from Other Namespaces | Namespace |
| NP-05 | 05-allow-traffic-from-all-namespaces.md | Allow Traffic from All Namespaces | Namespace |
| NP-06 | 06-allow-traffic-from-a-namespace.md | Allow Traffic from Namespace | Namespace |
| NP-07 | 07-allow-traffic-from-some-pods-in-another-namespace.md | Allow from Specific Pods | Advanced |
| NP-08 | 08-allow-external-traffic.md | Allow External Traffic | External |
| NP-09 | 09-allow-traffic-only-to-a-port.md | Allow Traffic to Port | Advanced |
| NP-10 | 10-allowing-traffic-with-multiple-selectors.md | Multiple Selectors | Advanced |
| NP-11 | 11-deny-egress-traffic-from-an-application.md | Deny Egress Traffic | Egress |
| NP-12 | 12-deny-all-non-whitelisted-traffic-from-the-namespace.md | Deny Non-Whitelisted Egress | Egress |
| NP-13 | **MISSING** | Allow Egress to Specific Pods | Egress |
| NP-14 | 14-deny-external-egress-traffic.md | Deny External Egress | Egress |

**Note**: Recipe NP-13 content exists in `combined-network-policies-prd.txt` but needs to be extracted to a separate markdown file.

## Quick Start

### 1. Prerequisites

```bash
# Ensure kubectl is installed and configured
kubectl version --client

# Connect to cluster with network policy support
gcloud container clusters create np \
    --enable-network-policy \
    --zone us-central1-b
```

### 2. Make Scripts Executable

```bash
chmod +x deploy-all-policies.sh
chmod +x test-all-policies.sh
chmod +x validate-recipes.sh
```

### 3. Validate Recipes

```bash
./validate-recipes.sh
```

### 4. Deploy Policies

```bash
# Dry-run first
./deploy-all-policies.sh --dry-run

# Deploy to production
./deploy-all-policies.sh --namespace production
```

### 5. Run Tests

```bash
./test-all-policies.sh
```

## Common Workflows

### Workflow 1: Test Single Recipe

```bash
# Extract YAML from specific recipe
grep -A 50 '```yaml' 01-deny-all-traffic-to-an-application.md | \
  sed '/```yaml/d;/```/d' > policy.yaml

# Apply policy
kubectl apply -f policy.yaml

# Test manually
kubectl run test --image=nginx
kubectl exec test -- wget -q -O- http://target-app
```

### Workflow 2: Progressive Deployment

```bash
# Deploy policies one at a time with verification
for recipe in 0{1..9}-*.md 1{0..4}-*.md; do
  echo "Deploying: $recipe"
  ./deploy-all-policies.sh --namespace demo
  ./test-all-policies.sh --namespace demo
  read -p "Continue? (y/n) " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || break
done
```

### Workflow 3: Cleanup All Policies

```bash
# Delete all network policies in namespace
kubectl delete networkpolicies --all -n <namespace>

# Or delete entire namespace
kubectl delete namespace <namespace>
```

## Troubleshooting

### Issue: NetworkPolicy not supported

**Error**: `error: the server doesn't have a resource type "networkpolicies"`

**Solution**:
```bash
# Check if NetworkPolicy API is available
kubectl api-resources | grep networkpolicies

# If not available, create cluster with network policy support
gcloud container clusters create np --enable-network-policy --zone us-central1-b
```

### Issue: Policies not working

**Symptoms**: Traffic is allowed when it should be blocked

**Debug Steps**:
```bash
# 1. Verify policy is applied
kubectl get networkpolicies -A

# 2. Describe the policy
kubectl describe networkpolicy <policy-name> -n <namespace>

# 3. Check pod labels
kubectl get pods --show-labels -n <namespace>

# 4. Check if CNI supports network policies
kubectl get pods -n kube-system | grep -E "calico|cilium|weave"
```

### Issue: Test failures

**Symptoms**: Tests fail unexpectedly

**Debug Steps**:
```bash
# 1. Check test pods are running
kubectl get pods -n policy-demo

# 2. Check pod connectivity
kubectl exec -n policy-demo api -- ping web

# 3. View test pod logs
kubectl logs -n policy-demo test-pod

# 4. Run tests in verbose mode
./test-all-policies.sh --verbose
```

## Best Practices

1. **Always Test in Non-Production First**
   - Use a dedicated test namespace
   - Validate policies before production deployment
   - Use dry-run mode for validation

2. **Start with Deny-All**
   - Begin with NP-01 (deny-all)
   - Progressively add allow rules
   - Test after each policy addition

3. **Label Everything**
   - Ensure all pods have meaningful labels
   - Document label conventions
   - Use consistent label schemas

4. **Monitor Policy Effects**
   - Check pod connectivity after applying policies
   - Use metrics to track denied connections
   - Log policy violations for audit

5. **Version Control**
   - Store policies in Git
   - Tag policy versions
   - Document policy changes

## Integration with CI/CD

### GitLab CI Example

```yaml
network-policy-validation:
  script:
    - ./validate-recipes.sh
  only:
    - merge_requests

network-policy-deploy:
  script:
    - ./deploy-all-policies.sh --namespace production
  only:
    - master

network-policy-test:
  script:
    - ./test-all-policies.sh
  only:
    - merge_requests
```

### GitHub Actions Example

```yaml
name: Network Policy CI

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Validate recipes
        run: ./validate-recipes.sh

  test:
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - uses: actions/checkout@v2
      - name: Setup cluster
        run: kind create cluster
      - name: Run tests
        run: ./test-all-policies.sh
```

## Contributing

To add a new recipe:

1. Create markdown file with naming convention: `NN-description.md`
2. Include required sections (see validate-recipes.sh)
3. Add YAML frontmatter with metadata
4. Include NetworkPolicy YAML example
5. Add test commands and verification steps
6. Run validation: `./validate-recipes.sh`
7. Update this guide with new recipe entry

## References

- [Kubernetes Network Policies Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Policy Recipes Repository](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Calico Network Policy](https://docs.projectcalico.org/security/calico-network-policy)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/policy/)

## License

Same license as the parent repository.
