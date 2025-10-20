---
id: NP-03
title: Deny All Non-Whitelisted Traffic in a Namespace
type: policy
category: namespaces
priority: critical
status: ready
estimated_time: 10m
dependencies: [NP-00]
tags: [network-policy, deny-all, namespace, default-deny, best-practice, zero-trust]
---

## Overview

Implement a fundamental default-deny NetworkPolicy that blocks all cross-pod networking in a namespace except traffic explicitly whitelisted via other Network Policies.

## Objectives

- Establish default-deny posture for namespace security
- Block all pod-to-pod traffic by default
- Create foundation for whitelist-based network policies
- Implement zero-trust networking principles at namespace level

## Background

This is a fundamental policy that blocks all cross-pod networking except connections explicitly whitelisted via other Network Policies deployed in the namespace.

**Use Case:** This is a foundational security practice for any namespace where workloads are deployed (except system namespaces like `kube-system`).

**Best Practice:** This policy provides default "deny all" functionality, allowing you to clearly identify component dependencies and deploy Network Policies that translate to dependency graphs between components. Start with this policy, then explicitly whitelist necessary traffic.

![Diagram of DENY all non-whitelisted traffic policy](img/3.gif)

## Requirements

### Task 1: Create Default Deny-All Policy
**Priority:** Critical
**Status:** pending

Create and apply the default deny-all NetworkPolicy manifest.

**Actions:**
- Create `default-deny-all.yaml` manifest
- Configure empty pod selector (matches all pods)
- Configure empty ingress rules (denies all traffic)
- Apply to target namespace

**Manifest:** `default-deny-all.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  ingress: []
```

**Key Configuration Points:**
- `namespace: default` - Deploy to the `default` namespace (change as needed)
- `podSelector: {}` - Empty selector matches ALL pods in the namespace
- `ingress: []` - Empty ingress array denies all incoming traffic

**How It Works:**
- Empty `podSelector` means policy applies to all pods in namespace
- Empty `ingress` array means no traffic is allowed
- Can also omit `ingress` field entirely (same effect)
- Only affects pods in the specified namespace

**Command:**
```bash
kubectl apply -f default-deny-all.yaml
```

**Expected Output:**
```
networkpolicy "default-deny-all" created
```

### Task 2: Verify Policy Deployment
**Priority:** High
**Status:** pending

Confirm the policy was created and is active.

**Actions:**
- Check policy exists
- Verify policy configuration
- Review affected pods

**Commands:**
```bash
kubectl get networkpolicy -n default
kubectl describe networkpolicy default-deny-all -n default
kubectl get pods -n default
```

## Acceptance Criteria

- [ ] NetworkPolicy `default-deny-all` created in target namespace
- [ ] Policy applies to all pods (empty podSelector)
- [ ] All ingress traffic is blocked (empty ingress rules)
- [ ] Policy is active and enforced
- [ ] Existing pods in namespace are now protected
- [ ] New pods deployed to namespace automatically protected
- [ ] Traffic between pods in namespace is blocked by default

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `default-deny-all`
- API Version: `networking.k8s.io/v1`
- Scope: Namespace-level (applies to all pods in specified namespace)
- Pod Selector: `{}` (empty - matches all pods)
- Ingress Rules: `[]` (empty array - denies all ingress)

**Behavior Details:**
- Applies to all pods in the namespace immediately
- Blocks all incoming traffic to all pods
- Does not affect egress (outbound) traffic
- Does not affect pods in other namespaces
- Other NetworkPolicies can whitelist specific traffic

**Namespace Considerations:**
- Deploy to application namespaces
- Do NOT deploy to `kube-system` namespace (will break cluster)
- Consider deploying to all non-system namespaces as default
- Can be overridden by additional NetworkPolicies

## Implementation Details

This policy is the cornerstone of a zero-trust network architecture in Kubernetes:

1. **Default Deny**: Without this policy, all traffic is allowed by default
2. **Explicit Allow**: After applying this, you must explicitly whitelist necessary traffic
3. **Additive Policies**: Additional NetworkPolicies can allow specific traffic
4. **Dependency Mapping**: Forces you to document and understand service dependencies

**Alternative Syntax:**

These three forms are equivalent:
```yaml
# Form 1: Empty array (recommended)
ingress: []

# Form 2: Null value
ingress:

# Form 3: Omitted field
spec:
  podSelector: {}
  # ingress field omitted
```

## Verification

Verify the policy is working by attempting to connect between pods:

```bash
# Deploy two test pods
kubectl run pod1 --image=nginx -n default
kubectl run pod2 --image=alpine -n default -- sleep 3600

# Try to connect from pod2 to pod1 (should fail)
kubectl exec pod2 -n default -- wget -qO- --timeout=2 http://pod1
# Expected: timeout or connection refused
```

## Cleanup

### Task: Remove Policy
To remove the default-deny policy:

```bash
kubectl delete networkpolicy default-deny-all -n default
```

**Warning:** Only remove this policy if you understand the security implications. Removing it will allow all traffic between pods in the namespace.

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Policy Best Practices](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-policies)
- [Zero Trust Networking](https://www.nist.gov/publications/zero-trust-architecture)

## Real-World Examples

### Example 1: Production Namespace Zero-Trust Foundation
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
  annotations:
    description: "Baseline zero-trust policy for production namespace"
    created-by: "security-team"
    enforcement-date: "2025-01-15"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress: []
```

**Use Case:** Establish zero-trust foundation in production namespace. All services must explicitly define allowed traffic sources. This forces teams to document dependencies and prevents accidental exposure.

### Example 2: Multi-Tenant SaaS Platform
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-isolation-default-deny
  namespace: tenant-a
  annotations:
    tenant-id: "tenant-a-uuid"
    compliance: "SOC2, HIPAA"
spec:
  podSelector: {}
  ingress: []
```

**Use Case:** In multi-tenant environments, apply default-deny to each tenant's namespace to ensure complete isolation between tenants. Prevents tenant A from accidentally or maliciously accessing tenant B's services.

### Example 3: Microservices Namespace with Service Mesh
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ecommerce-services
  annotations:
    service-mesh: "istio"
    allow-sidecar: "true"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  # Allow Istio sidecar injection
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: istio-system
    ports:
    - port: 15017  # Istio sidecar
  # All other traffic denied by default
```

**Use Case:** When using service mesh (Istio, Linkerd), default-deny must allow sidecar proxy traffic while blocking everything else. Additional policies whitelist service-to-service communication.

### Example 4: Development Namespace with Monitoring Exception
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-allow-monitoring
  namespace: development
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  # Allow Prometheus metrics scraping
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - port: 9090  # Metrics port
  # All other traffic denied
```

**Use Case:** Development namespace with default-deny but automatic exception for monitoring. Teams don't need to whitelist Prometheus individually for each service.

## Debugging Tips

**Verify Namespace-Wide Policy:**
```bash
# Check policy exists in namespace
kubectl get networkpolicy -n production

# Describe the default-deny policy
kubectl describe networkpolicy default-deny-all -n production

# View full YAML
kubectl get networkpolicy default-deny-all -n production -o yaml

# Check which namespaces have default-deny policies
kubectl get networkpolicy --all-namespaces | grep default-deny
```

**Verify Policy Scope:**
```bash
# List all pods affected by policy
kubectl get pods -n production --show-labels

# Check if new pods are automatically covered
kubectl run test-coverage --image=nginx -n production
kubectl exec test-coverage -n production -- wget -qO- --timeout=2 http://nginx
# Should timeout (proving policy applies)

# Verify policy selector matches all pods
kubectl get networkpolicy default-deny-all -n production -o jsonpath='{.spec.podSelector}'
# Should return: {}
```

**Test Inter-Pod Communication:**
```bash
# Deploy two test pods in namespace
kubectl run nginx -n production --image=nginx --port=80
kubectl run alpine -n production --image=alpine -- sleep 3600

# Attempt connection (should fail with default-deny)
kubectl exec alpine -n production -- wget -qO- --timeout=2 http://nginx
# Expected: wget: download timed out

# Test from different namespace (should also fail)
kubectl run test-cross-ns -n default --image=alpine --rm -i -t -- sh
# Inside: wget -qO- --timeout=2 http://nginx.production
```

**Identify Affected Services:**
```bash
# Find services that stopped working after policy
kubectl get events -n production --sort-by='.lastTimestamp' | grep -i fail

# Check pod readiness (may fail if probes can't connect)
kubectl get pods -n production -o wide

# Describe pods with connectivity issues
kubectl describe pod <pod-name> -n production | grep -i "readiness\|liveness"

# View application logs for connection errors
kubectl logs <pod-name> -n production | grep -i "connection refused\|timeout"
```

**Whitelist Policy Testing:**
```bash
# After creating whitelist policies, test connectivity
kubectl get networkpolicy -n production

# Verify multiple policies combine correctly
kubectl describe pod <pod-name> -n production

# Test specific service connectivity
kubectl run test-${RANDOM} -n production --rm -i -t --image=alpine -- \
  wget -qO- --timeout=2 http://<service-name>
```

**CNI Plugin Verification:**
```bash
# Check if CNI enforces policies (Calico example)
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep -i policy

# Verify NetworkPolicy enforcement
kubectl get felixconfiguration -n kube-system  # Calico-specific

# Check for policy enforcement errors
kubectl get events -n kube-system --field-selector involvedObject.kind=NetworkPolicy
```

**Namespace Label Debugging:**
```bash
# View namespace labels (important for namespaceSelector)
kubectl get namespace production --show-labels

# Describe namespace
kubectl describe namespace production

# Add label to namespace if missing
kubectl label namespace production environment=production

# Check all namespace labels
kubectl get namespaces --show-labels
```

## Common Mistakes

**1. Applying to kube-system Namespace**
```bash
# ❌ CRITICAL MISTAKE: Will break cluster!
kubectl apply -f default-deny-all.yaml -n kube-system
# Cluster DNS, API server communication, etc. will fail

# ✅ CORRECT: Skip system namespaces
kubectl get namespaces | grep -v kube
# Apply only to application namespaces
```

**Solution:** Create exemption list:
```bash
# Safe namespaces for default-deny
SAFE_NAMESPACES="production staging development"

for ns in $SAFE_NAMESPACES; do
  kubectl apply -f default-deny-all.yaml -n $ns
done
```

**2. Forgetting to Whitelist Health Probes**
```yaml
# ❌ PROBLEM: Pods fail readiness/liveness checks
# Kubelet can't reach pod probe endpoints
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
    # Default-deny blocks kubelet probe!
```

**Solution:** Probes from kubelet are typically allowed by default since they originate from the node, not from pods. However, if using custom health check pods:
```yaml
# Whitelist health check pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-health-checks
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: health-checker
    ports:
    - port: 8080
```

**3. Not Considering Service Mesh Sidecars**
```yaml
# ❌ PROBLEM: Service mesh can't inject sidecar or communicate
# Istio, Linkerd, Consul need to communicate with pods

# ✅ SOLUTION: Allow service mesh namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-allow-mesh
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
```

**4. Assuming Egress is Also Blocked**
```yaml
# ⚠️ MISCONCEPTION: This ONLY blocks ingress
spec:
  podSelector: {}
  ingress: []
  # Egress is still ALLOWED!
```

**To block both ingress and egress:**
```yaml
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
  # Now both directions are blocked
```

**5. Race Condition During Deployment**
```bash
# ❌ PROBLEM: Deploy apps before default-deny
kubectl apply -f app-deployment.yaml -n production
kubectl apply -f default-deny-all.yaml -n production
# Apps break because no whitelist policies exist

# ✅ CORRECT: Apply default-deny first, then apps with whitelist
kubectl apply -f default-deny-all.yaml -n production
kubectl apply -f whitelist-policies/ -n production
kubectl apply -f app-deployment.yaml -n production
```

**6. Not Testing Before Production**
```bash
# ❌ WRONG: Apply directly to production
kubectl apply -f default-deny-all.yaml -n production
# Breaks running services!

# ✅ CORRECT: Test in non-prod first
kubectl apply -f default-deny-all.yaml -n development
# Identify broken services
# Create whitelist policies
# Test in staging
# Finally apply to production
```

**7. Confusing Namespace Scope**
```bash
# ❌ MISCONCEPTION: Policy affects all namespaces
kubectl apply -f default-deny-all.yaml
# Only affects 'default' namespace!

# ✅ CORRECT: Apply to each namespace explicitly
kubectl apply -f default-deny-all.yaml -n production
kubectl apply -f default-deny-all.yaml -n staging
```

**8. Not Documenting Whitelist Requirements**
```bash
# ❌ PROBLEM: Team doesn't know what to whitelist
# Developers waste time debugging connectivity

# ✅ SOLUTION: Create documentation
cat > NETWORK-POLICY-README.md <<EOF
# Network Policies in Production Namespace

## Default Policy
- Deny-all baseline applied
- All traffic must be explicitly whitelisted

## Required Whitelists
1. Frontend → Backend API (port 8080)
2. Backend → Database (port 5432)
3. All → Monitoring (port 9090)

## How to Add Whitelist
See examples in policies/whitelist/
EOF
```

## Security Considerations

**Zero-Trust Architecture Foundation:**

Default-deny namespace policies are the cornerstone of zero-trust networking in Kubernetes:

```
Traditional Security Model:
├─ Trust internal network by default
├─ Firewall at perimeter only
└─ East-west traffic unrestricted

Zero-Trust Model with Default-Deny:
├─ Trust nothing by default
├─ Verify every connection
├─ Explicit whitelist required
└─ Micro-segmentation everywhere
```

**What Default-Deny Protects Against:**
- ✅ Lateral movement by compromised pods
- ✅ Accidental exposure of internal services
- ✅ Rogue pods accessing sensitive data
- ✅ Blast radius of security incidents
- ✅ Unauthorized inter-service communication
- ✅ Cross-tenant data leakage (multi-tenant environments)
- ✅ Development/test pods reaching production services

**What Default-Deny DON'T Protect Against:**
- ❌ Attacks within explicitly allowed traffic flows
- ❌ Application-layer vulnerabilities
- ❌ Compromised credentials or tokens
- ❌ Supply chain attacks in container images
- ❌ Privilege escalation within containers
- ❌ Host-level vulnerabilities

**Defense-in-Depth Strategy:**

Default-deny should be **one layer** in a comprehensive security strategy:

1. **Network Layer** (this policy):
   - Default-deny namespace policies
   - Explicit whitelist policies
   - Egress controls

2. **Identity Layer**:
   - Service accounts with minimal permissions
   - RBAC for API access
   - mTLS for service-to-service auth

3. **Application Layer**:
   - Authentication and authorization
   - Input validation
   - Rate limiting

4. **Runtime Layer**:
   - Pod Security Standards
   - Seccomp profiles
   - AppArmor/SELinux

5. **Supply Chain Layer**:
   - Image scanning
   - Binary authorization
   - SBOM tracking

**Best Practices for Production:**

**1. Rollout Strategy:**
```bash
# Week 1: Observation
# Apply to dev namespace
kubectl apply -f default-deny-all.yaml -n development
# Monitor for issues
kubectl get events -n development --watch

# Week 2-3: Create Whitelists
# Document all required connectivity
# Create whitelist policies
kubectl apply -f policies/whitelist/ -n development

# Week 4: Staging
kubectl apply -f default-deny-all.yaml -n staging
kubectl apply -f policies/whitelist/ -n staging
# Monitor for 1 week

# Week 5+: Production
# Apply during low-traffic window
kubectl apply -f default-deny-all.yaml -n production
kubectl apply -f policies/whitelist/ -n production
# Have rollback plan ready
```

**2. Policy as Code:**
```bash
# Store policies in Git
git-repo/
├── base/
│   └── default-deny-all.yaml
├── overlays/
│   ├── production/
│   │   └── kustomization.yaml
│   └── staging/
│       └── kustomization.yaml
└── whitelist/
    ├── frontend-to-backend.yaml
    └── backend-to-database.yaml

# Deploy with GitOps
kubectl apply -k overlays/production/
```

**3. Compliance Documentation:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
  annotations:
    compliance.frameworks: "PCI-DSS 1.2.1, HIPAA 164.312(a), SOC2 CC6.6"
    security.control-id: "NET-001"
    risk.rating: "critical"
    audit.last-reviewed: "2025-01-15"
    audit.reviewer: "security-team@company.com"
    audit.frequency: "quarterly"
spec:
  podSelector: {}
  ingress: []
```

**4. Monitoring and Alerting:**
```bash
# Alert on policy deletions
kubectl get events --watch | grep -i "NetworkPolicy.*deleted"

# Monitor for denied connections
kubectl logs -n kube-system -l k8s-app=calico-node | grep DENY

# Track policy coverage
kubectl get networkpolicy --all-namespaces -o json | \
  jq '.items | map(select(.spec.podSelector == {})) | length'
```

**5. Exception Management:**
```yaml
# Document exceptions
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-legacy-app
  annotations:
    exception.reason: "Legacy app needs broad access during migration"
    exception.approved-by: "security-lead@company.com"
    exception.expiry-date: "2025-06-30"
    exception.jira: "SEC-789"
    exception.owner: "platform-team"
spec:
  podSelector:
    matchLabels:
      app: legacy-crm
  ingress:
  - from:
    - namespaceSelector: {}  # Allow from any namespace temporarily
```

**Attack Scenario Comparison:**

**Scenario 1: Compromised Pod Lateral Movement**
```
WITHOUT Default-Deny:
Attacker compromises web pod
  → ✓ Scans entire namespace
  → ✓ Finds database pod
  → ✓ Connects to database
  → ✓ Exfiltrates data
  → ✓ Spreads to other pods

WITH Default-Deny:
Attacker compromises web pod
  → ✗ Cannot scan (connections blocked)
  → ✗ Cannot reach database (no whitelist)
  → ✓ Can only communicate with API gateway (whitelisted)
  → ✗ Lateral movement contained
```

**Scenario 2: Rogue Development Pod**
```
WITHOUT Default-Deny:
Developer accidentally deploys test pod to production
  → ✓ Test pod can access production database
  → ✓ Can read customer data
  → ✓ Could corrupt data with test queries

WITH Default-Deny:
Developer deploys test pod to production
  → ✗ Test pod has no network access
  → ✗ Cannot reach database
  → ✗ Cannot affect production services
  → ✓ Fails fast, easy to identify
```

**Compliance Considerations:**

**PCI-DSS Requirements:**
- Requirement 1.2.1: "Restrict inbound and outbound traffic"
- Requirement 1.3: "Prohibit direct public access between the Internet and any system component"
- Default-deny satisfies internal network segmentation requirements

**HIPAA Requirements:**
- §164.312(a)(1): "Access control to ePHI"
- §164.312(e)(1): "Transmission security"
- Demonstrates technical safeguards for PHI access

**SOC 2 Controls:**
- CC6.6: "Logical and Physical Access Controls"
- CC6.7: "Restricts Access to System Resources"
- Provides evidence of network segmentation

**GDPR Article 32:**
- "Security of processing"
- "Ability to ensure ongoing confidentiality"
- Network isolation protects personal data

## Best Practices

**When to Apply Default-Deny:**

**✅ Always Apply To:**
- Production namespaces (critical)
- Staging namespaces (test realistic security)
- Namespaces with sensitive data (PII, financial, health)
- Multi-tenant environment namespaces
- Customer-facing service namespaces

**❌ Never Apply To:**
- `kube-system` namespace (breaks cluster)
- `kube-public` namespace (intended for public access)
- `kube-node-lease` namespace (node heartbeats)

**⚠️ Consider Carefully:**
- Development namespaces (may slow iteration)
- CI/CD namespaces (complex automation needs)
- Monitoring namespaces (needs broad access)
- Service mesh control planes (complex traffic patterns)

**Implementation Timeline:**

**Phase 1: Planning (Week 1-2)**
```bash
# Document current traffic flows
kubectl logs <pod> | grep "connection from"

# Use service mesh observability if available
istioctl dashboard kiali

# Create service dependency map
# Identify all inter-service communication
```

**Phase 2: Policy Creation (Week 3-4)**
```bash
# Create default-deny policy
cat > default-deny-all.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  ingress: []
EOF

# Create whitelist policies for each service
# Start with most critical services
```

**Phase 3: Testing (Week 5-6)**
```bash
# Apply to development namespace
kubectl apply -f default-deny-all.yaml -n development
kubectl apply -f whitelist-policies/ -n development

# Run integration tests
./run-integration-tests.sh

# Fix any connectivity issues
# Update whitelist policies as needed
```

**Phase 4: Staging Deployment (Week 7-8)**
```bash
# Apply to staging
kubectl apply -f default-deny-all.yaml -n staging
kubectl apply -f whitelist-policies/ -n staging

# Monitor for 2 weeks
kubectl get events -n staging --watch
kubectl logs -n kube-system -l k8s-app=calico-node | grep DENY

# Load test with realistic traffic
```

**Phase 5: Production Deployment (Week 9+)**
```bash
# Choose low-traffic window
# Have team on standby

# Apply policies
kubectl apply -f default-deny-all.yaml -n production
kubectl apply -f whitelist-policies/ -n production

# Monitor closely
kubectl get events -n production --watch

# Have rollback ready
kubectl delete networkpolicy default-deny-all -n production
```

**Namespace Management:**
```bash
# Apply to multiple namespaces
for ns in production staging development; do
  kubectl apply -f default-deny-all.yaml -n $ns
done

# Verify coverage
kubectl get networkpolicy --all-namespaces | \
  grep default-deny-all

# Create new namespace with policy
kubectl create namespace new-service
kubectl apply -f default-deny-all.yaml -n new-service
kubectl label namespace new-service default-deny=enabled
```

**GitOps Integration:**
```yaml
# Kustomization for multiple namespaces
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
- default-deny-all.yaml
- ../whitelist-policies

patches:
- patch: |-
    - op: replace
      path: /metadata/annotations/environment
      value: production
  target:
    kind: NetworkPolicy
```

**Testing Checklist:**
- [ ] Default-deny applied to namespace
- [ ] All existing services still functional
- [ ] New pods automatically protected
- [ ] Health checks still passing
- [ ] Monitoring/logging still working
- [ ] CI/CD pipelines still functional
- [ ] Cross-namespace communication tested
- [ ] Emergency rollback procedure tested

**Documentation Template:**
```markdown
# Network Policy: Default-Deny

## Overview
Namespace-wide default-deny policy for zero-trust networking.

## Affected Namespaces
- production
- staging
- development

## Whitelist Policies
1. `frontend-to-backend` - Allows web tier to API tier
2. `backend-to-database` - Allows API tier to data tier
3. `allow-monitoring` - Allows Prometheus scraping
4. `allow-ingress` - Allows ingress controller traffic

## Emergency Rollback
```bash
# Remove default-deny (traffic flows again)
kubectl delete networkpolicy default-deny-all -n production
```

## Troubleshooting
If service breaks:
1. Check `kubectl describe pod <name> -n production`
2. Look for connection timeouts in logs
3. Create temporary whitelist policy
4. Contact security-team@company.com

## Compliance
- PCI-DSS: Requirement 1.2.1
- HIPAA: §164.312(a)
- SOC 2: CC6.6
```

## Notes

**Key Takeaways:**
- This is the **foundation** of zero-trust networking in Kubernetes
- Apply to **all application namespaces** (never kube-system)
- **Test thoroughly** before production deployment
- **Document all whitelists** for maintenance
- Combine with egress policies for complete control
- Have **rollback plan** ready
- Monitor policy effectiveness continuously

**Critical Reminders:**
- ⚠️ **NEVER apply to kube-system** - will break cluster
- ✅ **Always test in non-prod first**
- ✅ **Document service dependencies** before applying
- ✅ **Create whitelist policies** before deploying apps
- ✅ **Have rollback procedure** ready
- ✅ **Monitor for denied connections** after deployment

**Next Steps:**
After implementing namespace-wide default-deny:
1. **NP-01, NP-02**: Create whitelist policies for specific services
2. **NP-12**: Add egress default-deny for complete zero-trust
3. **NP-06, NP-07**: Implement cross-namespace policies
4. **NP-09**: Add port-level restrictions

**Common Patterns:**

**Three-Tier Application:**
```
Namespace: production (default-deny)
├── Frontend Tier (allow from ingress)
├── Backend Tier (allow from frontend)
└── Database Tier (allow from backend)
```

**Microservices with Service Mesh:**
```
Namespace: services (default-deny + allow mesh)
├── Service A (allow from gateway + mesh)
├── Service B (allow from serviceA + mesh)
└── Service C (allow from serviceB + mesh)
```

**Multi-Tenant SaaS:**
```
Namespace: tenant-a (default-deny)
Namespace: tenant-b (default-deny)
Namespace: tenant-c (default-deny)
Namespace: shared-services (selective allow from all tenants)
```

**Remember:** Default-deny is not the end goal—it's the starting point. You must follow up with explicit whitelist policies for legitimate traffic. Without whitelists, applications cannot communicate.
