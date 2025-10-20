---
id: NP-02
title: Limit Traffic to an Application
type: policy
category: basics
priority: high
status: ready
estimated_time: 15m
dependencies: [NP-00]
tags: [network-policy, whitelist, pod-selector, ingress, microservices]
---

## Overview

Create a NetworkPolicy that allows traffic from only specific Pods using label selectors, implementing a whitelist-based security model.

## Objectives

- Restrict traffic to a service only from authorized microservices
- Implement pod-to-pod communication policies using labels
- Demonstrate whitelist-based network security
- Verify both blocked and allowed traffic patterns

## Background

NetworkPolicies allow you to create rules that permit traffic from only certain Pods based on label selectors. This is essential for implementing zero-trust networking and microservices security.

**Use Cases:**
- Restrict traffic to a service only to other microservices that need to use it
- Restrict connections to a database only to the application using it
- Implement service mesh security without additional infrastructure
- Control inter-service communication in microservices architecture

![Diagram of LIMIT traffic to an application policy](img/2.gif)

## Requirements

### Task 1: Deploy API Server Application
**Priority:** High
**Status:** pending

Deploy a REST API server application with specific labels.

**Actions:**
- Run nginx as API server with labels `app=bookstore` and `role=api`
- Expose the service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run apiserver --image=nginx --labels="app=bookstore,role=api" --expose --port=80
```

### Task 2: Create NetworkPolicy
**Priority:** High
**Status:** pending

Create NetworkPolicy to restrict access only to pods with matching labels.

**Actions:**
- Create `api-allow.yaml` manifest
- Configure pod selector for target pods
- Configure ingress rules for allowed sources
- Apply policy to cluster

**Manifest:** `api-allow.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: api-allow
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: api
  ingress:
  - from:
      - podSelector:
          matchLabels:
            app: bookstore
```

**Command:**
```bash
kubectl apply -f api-allow.yaml
```

**Expected Output:**
```
networkpolicy "api-allow" created
```

### Task 3: Test Blocked Traffic
**Priority:** High
**Status:** pending

Verify that pods without the required label cannot access the API server.

**Actions:**
- Run test pod without `app=bookstore` label
- Attempt HTTP connection with timeout
- Confirm connection is blocked

**Command:**
```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://apiserver
```

**Expected Result:**
```
wget: download timed out
```

Traffic is blocked!

### Task 4: Test Allowed Traffic
**Priority:** High
**Status:** pending

Verify that pods with the correct label can access the API server.

**Actions:**
- Run test pod with `app=bookstore` label
- Make HTTP connection
- Confirm successful response

**Command:**
```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine --labels="app=bookstore,role=frontend" -- sh
# Inside the pod:
wget -qO- --timeout=2 http://apiserver
```

**Expected Result:**
```html
<!DOCTYPE html>
<html><head>
```

Traffic is allowed!

## Acceptance Criteria

- [ ] API server pod deployed with labels `app=bookstore` and `role=api`
- [ ] Service exposed on port 80
- [ ] NetworkPolicy `api-allow` created successfully
- [ ] Policy targets pods with correct labels
- [ ] Traffic from non-matching pods is blocked (timeout)
- [ ] Traffic from matching pods is allowed (successful response)
- [ ] Policy only affects specified pods, not cluster-wide

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `api-allow`
- API Version: `networking.k8s.io/v1`
- Target Pods: `app=bookstore` AND `role=api`
- Allowed Sources: Pods with `app=bookstore` label

**How It Works:**
- `podSelector` specifies which pods the policy applies to (target pods)
- `ingress.from.podSelector` specifies which pods can send traffic (source pods)
- Only pods matching the source selector can connect
- All other traffic is denied by default
- Policy is namespace-scoped

**Label Matching:**
- Target: Pods must have BOTH `app=bookstore` AND `role=api` labels
- Source: Pods need only `app=bookstore` label to access
- Labels on source pods determine access rights
- Non-matching pods are automatically blocked

## Implementation Details

The NetworkPolicy uses label selectors to create fine-grained access control:

1. **Target Selection**: The `spec.podSelector` matches pods with both `app=bookstore` and `role=api` labels
2. **Source Selection**: The `ingress.from.podSelector` allows traffic from any pod with `app=bookstore` label
3. **Default Deny**: Once a NetworkPolicy targets a pod, all non-matching traffic is denied
4. **Namespace Scope**: Both selectors operate within the same namespace by default

## Verification

Check policy status:
```bash
kubectl get networkpolicy
kubectl describe networkpolicy api-allow
kubectl get pods --show-labels
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod apiserver
kubectl delete service apiserver
kubectl delete networkpolicy api-allow
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Pod Selector Specification](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)

## Real-World Examples

### Example 1: Database Access Control
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-allow-backend-only
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgresql
      role: database
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
          access: database
    ports:
    - protocol: TCP
      port: 5432
```

**Use Case:** Allow only backend application pods to access the PostgreSQL database on port 5432. Frontend and other services cannot connect directly to the database, enforcing proper architecture layers.

### Example 2: API Gateway Pattern
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: internal-api-whitelist
  namespace: services
spec:
  podSelector:
    matchLabels:
      app: internal-api
      tier: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: api-gateway
    - podSelector:
        matchLabels:
          role: admin-console
    ports:
    - protocol: TCP
      port: 8080
```

**Use Case:** Internal API service accepts connections only from the API gateway and admin console. This creates a controlled entry point for the internal API.

### Example 3: Microservices Communication
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: order-service
  ingress:
  # Allow from cart service
  - from:
    - podSelector:
        matchLabels:
          app: cart-service
    ports:
    - protocol: TCP
      port: 8080
  # Allow from inventory service
  - from:
    - podSelector:
        matchLabels:
          app: inventory-service
    ports:
    - protocol: TCP
      port: 8080
```

**Use Case:** Order service accepts requests only from cart service and inventory service. Payment service and other services cannot access order service directly, enforcing service mesh boundaries.

### Example 4: Monitoring Access Pattern
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-allow-monitoring
  namespace: production
spec:
  podSelector:
    matchLabels:
      monitoring: "true"
  ingress:
  # Allow application traffic
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
  # Allow Prometheus scraping
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9090
```

**Use Case:** Application accepts both user traffic on port 8080 and Prometheus metrics scraping on port 9090, with different sources for each port.

## Debugging Tips

**Verify Policy and Pod Labels:**
```bash
# Check if policy exists and view details
kubectl get networkpolicy
kubectl describe networkpolicy api-allow

# View policy YAML
kubectl get networkpolicy api-allow -o yaml

# Check API server pod labels
kubectl get pod apiserver --show-labels

# Check all pods in namespace
kubectl get pods --show-labels

# Verify specific label
kubectl get pod apiserver -o jsonpath='{.metadata.labels.app}'
```

**Test Connectivity from Different Sources:**
```bash
# Test from pod WITHOUT required label (should fail)
kubectl run test-blocked --rm -i -t --image=alpine --labels="app=other" -- sh
# Inside: wget -qO- --timeout=2 http://apiserver

# Test from pod WITH required label (should succeed)
kubectl run test-allowed --rm -i -t --image=alpine --labels="app=bookstore" -- sh
# Inside: wget -qO- --timeout=2 http://apiserver

# Test from existing pod
kubectl exec -it <pod-name> -- wget -qO- --timeout=2 http://apiserver
```

**Advanced Connectivity Testing:**
```bash
# Use netcat to test port connectivity
kubectl run netcat-test --rm -i -t --image=alpine --labels="app=bookstore" -- sh
# Inside:
nc -zv apiserver 80
telnet apiserver 80

# Use curl for detailed HTTP testing
kubectl run curl-test --rm -i -t --image=curlimages/curl --labels="app=bookstore" -- \
  curl -v --connect-timeout 2 http://apiserver

# Test with specific timeout
kubectl run timeout-test --rm -i -t --image=alpine --labels="app=bookstore" -- \
  timeout 2 wget -qO- http://apiserver
```

**Verify Service and Endpoints:**
```bash
# Check service configuration
kubectl get service apiserver
kubectl describe service apiserver

# Verify service endpoints point to correct pods
kubectl get endpoints apiserver

# Check if service selector matches pod labels
kubectl get service apiserver -o jsonpath='{.spec.selector}'
kubectl get pod apiserver -o jsonpath='{.metadata.labels}'
```

**Label Debugging:**
```bash
# Add label to pod for testing
kubectl label pod test-pod app=bookstore

# Remove label from pod
kubectl label pod test-pod app-

# Update existing label
kubectl label pod test-pod app=bookstore --overwrite

# Show label differences
kubectl get pods -L app,role,tier
```

**Policy Troubleshooting:**
```bash
# Check CNI plugin logs (Calico example)
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100

# Search for policy-related events
kubectl get events --sort-by='.lastTimestamp' | grep -i network

# Check if NetworkPolicy CRD exists
kubectl get crd networkpolicies.networking.k8s.io

# Verify CNI supports NetworkPolicy
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|antrea'
```

## Common Mistakes

**1. Label Mismatch Between Policy and Pods**
```yaml
# ❌ WRONG: Policy expects app=bookstore, but pod has app=book-store
spec:
  podSelector:
    matchLabels:
      app: bookstore  # Hyphen vs no hyphen!
      role: api
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: bookstore
```

**Solution:** Use exact label matching:
```bash
# Check actual pod labels
kubectl get pod apiserver -o jsonpath='{.metadata.labels}' | jq

# Verify labels match policy
kubectl describe networkpolicy api-allow | grep -A 5 "Pod Selector"
```

**2. Forgetting Multiple Labels Create AND Condition**
```yaml
# ⚠️ Target pods must have BOTH labels
spec:
  podSelector:
    matchLabels:
      app: bookstore  # AND
      role: api       # Both required
```

**Solution:** Understand label matching:
```bash
# This pod WILL match (has both labels)
kubectl label pod apiserver app=bookstore role=api

# This pod WON'T match (missing role=api)
kubectl label pod apiserver app=bookstore
```

**3. Assuming Policy Allows All Traffic**
```yaml
# ❌ MISCONCEPTION: This policy creates default-deny
# Once applied, ONLY pods with app=bookstore can connect
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: api
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: bookstore
```

**Reality:** The policy activates default-deny for the target pod. Only explicitly allowed traffic flows.

**4. Not Testing Both Positive and Negative Cases**
```bash
# ❌ INCOMPLETE: Only testing allowed traffic
kubectl run test --rm -i -t --image=alpine --labels="app=bookstore" -- \
  wget -qO- http://apiserver
# ✅ Success!

# ✅ COMPLETE: Also test blocked traffic
kubectl run test --rm -i -t --image=alpine --labels="app=other" -- \
  wget -qO- --timeout=2 http://apiserver
# Should timeout
```

**5. Confusing Namespace Scope**
```yaml
# ⚠️ WARNING: podSelector without namespaceSelector
# Only matches pods in the SAME namespace
ingress:
- from:
  - podSelector:
      matchLabels:
        app: bookstore
  # Implicitly same namespace only!
```

**To allow from different namespace:**
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: frontend
    podSelector:
      matchLabels:
        app: bookstore
```

**6. Service Port vs Container Port Confusion**
```yaml
# ⚠️ NetworkPolicy uses CONTAINER port, not SERVICE port
# Service: port 8080 → targetPort 80
# NetworkPolicy should specify port 80 (container port)

ports:
- protocol: TCP
  port: 80  # ✅ Container port
```

**7. Policy Applied to Wrong Namespace**
```bash
# ❌ WRONG: Policy in default namespace, pod in production
kubectl apply -f api-allow.yaml
kubectl get pod apiserver -n production

# ✅ CORRECT: Specify namespace
kubectl apply -f api-allow.yaml -n production
```

## Security Considerations

**Defense-in-Depth:**
- NetworkPolicies provide network-layer security
- Should be combined with:
  - **Application Authentication**: Verify identity within the application
  - **Authorization**: Check permissions even if network access is allowed
  - **Encryption**: Use TLS for sensitive traffic
  - **Audit Logging**: Log all access attempts
  - **Pod Security**: Restrict container capabilities

**What Whitelisting Protects Against:**
- ✅ Unauthorized pod-to-pod communication
- ✅ Accidental misconfigurations exposing services
- ✅ Lateral movement by compromised pods
- ✅ Blast radius of security incidents
- ✅ Development/test pods accessing production services

**What Whitelisting DON'T Protect Against:**
- ❌ Attacks from allowed sources
- ❌ Application-layer vulnerabilities
- ❌ Compromised credentials within allowed pods
- ❌ Data exfiltration through allowed channels
- ❌ Supply chain attacks in trusted images

**Best Practices for Whitelisting:**

**1. Principle of Least Privilege:**
```yaml
# ✅ GOOD: Specific labels for specific access
ingress:
- from:
  - podSelector:
      matchLabels:
        app: frontend
        version: v2
        access-tier: api
  ports:
  - port: 8080  # Only specific port
```

**2. Document Service Dependencies:**
```yaml
# ✅ GOOD: Use annotations to document
metadata:
  name: api-allow
  annotations:
    description: "Allow frontend v2 to access API"
    dependencies: "frontend-v2, admin-console"
    jira: "SEC-456"
    owner: "backend-team"
    reviewed: "2025-01-15"
```

**3. Regular Label Audits:**
```bash
# Audit pods with database access
kubectl get pods -l access=database --all-namespaces --show-labels

# Find pods that can access sensitive services
kubectl get pods --selector='tier=backend,access=payment' -o wide

# Review label consistency
kubectl get pods --show-labels | grep -E 'app|tier|role'
```

**4. Use Namespaces for Isolation:**
```yaml
# ✅ GOOD: Combine namespace and pod selectors
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: frontend
  # Only production frontend pods
```

**5. Monitor Policy Effectiveness:**
```bash
# Check for denied connections (Calico)
kubectl logs -n kube-system -l k8s-app=calico-node | grep -i deny

# Monitor pod connectivity issues
kubectl get events --field-selector reason=FailedConnection

# Audit NetworkPolicy changes
kubectl get events --field-selector involvedObject.kind=NetworkPolicy
```

**Attack Scenario Examples:**

**Scenario 1: Compromised Frontend Pod**
```
Without NetworkPolicy:
Frontend Pod (compromised) → ✓ Can access database directly
                          → ✓ Can access payment API
                          → ✓ Can reach internal services

With Whitelist NetworkPolicy:
Frontend Pod (compromised) → ✗ Cannot access database
                          → ✗ Cannot access payment API
                          → ✓ Can only access allowed API gateway
```

**Scenario 2: Label-Based Privilege Escalation Attempt**
```bash
# Attacker tries to add privileged label
kubectl label pod malicious-pod app=bookstore

# ✅ PROTECTED: If RBAC is configured correctly
Error from server (Forbidden): User cannot modify pod labels

# ❌ VULNERABLE: If RBAC allows label modification
# Attacker gains network access to API server
```

**Solution:** Restrict label modification with RBAC:
```yaml
# Prevent label changes in production
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: no-label-changes
  namespace: production
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
# No "patch" or "update" verb
```

**Compliance Considerations:**
- PCI-DSS: Requires network segmentation for cardholder data
- HIPAA: Mandates access controls for protected health information
- SOC 2: Demonstrates logical access controls
- GDPR: Shows data access restrictions

**Label Taxonomy Best Practices:**
```yaml
# ✅ RECOMMENDED: Hierarchical labeling scheme
labels:
  # Identity
  app: order-service
  component: api
  version: v2.1.0

  # Environment
  environment: production
  tier: backend

  # Security
  access-level: internal
  data-classification: pii

  # Operations
  team: ecommerce
  cost-center: engineering
  monitoring: prometheus
```

## Best Practices

**When to Use Whitelisting:**

**✅ Good Use Cases:**
- Microservices architectures with defined dependencies
- Database access control (only backend tier)
- API gateway patterns (controlled entry points)
- Multi-tier applications (frontend → backend → database)
- Monitoring integrations (allow Prometheus scraping)

**❌ Less Suitable For:**
- Services with dynamic, unpredictable access patterns
- Environments with frequently changing dependencies
- Development namespaces with rapid iteration
- Legacy applications without proper labeling

**Progressive Whitelisting Strategy:**

**Phase 1: Identify Dependencies (Week 1-2)**
```bash
# Monitor actual traffic patterns
kubectl logs <pod> | grep "connection from"

# Use service mesh observability (if available)
istioctl dashboard kiali

# Document service-to-service calls
# Create dependency map
```

**Phase 2: Label Consistently (Week 3)**
```bash
# Apply consistent labels to all pods
kubectl label pods -l tier=backend app=api-service
kubectl label pods -l tier=frontend app=web-ui

# Verify label coverage
kubectl get pods --show-labels
```

**Phase 3: Create Policies (Week 4)**
```bash
# Start with most critical services (databases, payment)
kubectl apply -f database-whitelist-policy.yaml

# Expand to backend services
kubectl apply -f backend-api-whitelist.yaml

# Finally to frontend
kubectl apply -f frontend-whitelist.yaml
```

**Phase 4: Test and Validate (Week 5)**
```bash
# Test each service endpoint
./test-all-endpoints.sh

# Monitor for blocked legitimate traffic
kubectl logs -n kube-system -l k8s-app=calico-node | grep DENY

# Adjust policies as needed
kubectl edit networkpolicy api-allow
```

**Multi-Environment Strategy:**
```bash
# Development: Permissive policies
kubectl apply -f policies/dev/ -n development

# Staging: Production-like policies
kubectl apply -f policies/prod/ -n staging

# Production: Strict whitelisting
kubectl apply -f policies/prod/ -n production
```

**Label Management:**
```bash
# Use label prefixes for organization
kubectl label pod api app.kubernetes.io/name=api-server
kubectl label pod api app.kubernetes.io/component=backend
kubectl label pod api app.kubernetes.io/part-of=ecommerce

# Custom domain for company labels
kubectl label pod api company.com/team=platform
kubectl label pod api company.com/cost-center=engineering
```

**Policy Testing Checklist:**
- [ ] Test with pods that should be allowed
- [ ] Test with pods that should be blocked
- [ ] Test from different namespaces
- [ ] Test after pod restarts
- [ ] Test after policy updates
- [ ] Verify service endpoints remain accessible
- [ ] Check application logs for connection errors
- [ ] Monitor CNI plugin logs for denials

**Documentation Template:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
  annotations:
    description: "Whitelists traffic from bookstore app pods to API server"
    rationale: "Implements principle of least privilege for API access"
    dependencies: "frontend pods with label app=bookstore"
    impact: "Blocks all non-bookstore pods from accessing API"
    rollback: "kubectl delete networkpolicy api-allow"
    contact: "platform-team@company.com"
    jira: "SEC-789"
    last-reviewed: "2025-01-15"
    review-frequency: "quarterly"
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: api
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: bookstore
```

## Notes

**Key Takeaways:**
- Whitelisting implements **principle of least privilege** at network layer
- Use **consistent labels** across all services
- **Test both allowed and blocked** traffic scenarios
- **Document dependencies** for maintenance
- Combine with RBAC to prevent label tampering
- **Regular audits** ensure policies remain effective

**Next Steps:**
After implementing basic whitelisting:
1. **NP-03**: Apply namespace-wide default-deny as foundation
2. **NP-06**: Learn cross-namespace whitelisting
3. **NP-09**: Add port-level restrictions
4. **NP-13**: Implement egress whitelisting

**Common Patterns:**
- **Three-tier app**: Frontend → Backend → Database (whitelist each tier)
- **API Gateway**: All traffic through gateway → backend services
- **Microservices**: Service mesh with explicit dependencies
- **Monitoring**: Allow Prometheus from monitoring namespace

**Remember:** NetworkPolicies are additive. Multiple policies targeting the same pod create a union of allowed traffic. This lets you compose complex access patterns from simple building blocks.
