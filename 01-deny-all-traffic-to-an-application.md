---
id: NP-01
title: Deny All Traffic to an Application
type: policy
category: basics
priority: high
status: ready
estimated_time: 15m
dependencies: [NP-00]
tags: [network-policy, deny-all, isolation, security, ingress]
---

## Overview

Implement a NetworkPolicy that drops all traffic to pods of an application using Pod Selectors to achieve complete network isolation.

## Objectives

- Create a deny-all NetworkPolicy for specific application pods
- Block all incoming traffic to selected pods
- Verify traffic isolation is working correctly
- Understand the foundation for whitelisting traffic

## Background

This NetworkPolicy drops all traffic to pods of an application selected using Pod Selectors. This is a fundamental pattern in Kubernetes network security.

**Use Cases:**
- Start whitelisting traffic using Network Policies (first blacklist, then whitelist)
- Run a Pod and prevent any other Pods from communicating with it
- Temporarily isolate traffic to a Service from other Pods
- Implement zero-trust networking principles

![Diagram for DENY all traffic to an application policy](img/1.gif)

## Requirements

### Task 1: Deploy Test Application
**Priority:** High
**Status:** pending

Deploy a test nginx application to demonstrate the policy.

**Actions:**
- Run nginx Pod with label `app=web`
- Expose the Pod at port 80
- Verify initial connectivity

**Command:**
```bash
kubectl run web --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Test Initial Connectivity
**Priority:** High
**Status:** pending

Verify that the web service is accessible before applying the policy.

**Actions:**
- Run temporary test Pod
- Make HTTP request to web Service
- Confirm successful response

**Command:**
```bash
kubectl run --rm -i -t --image=alpine test-$RANDOM -- sh
# Inside the pod:
wget -qO- http://web
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
...
```

### Task 3: Create and Apply NetworkPolicy
**Priority:** High
**Status:** pending

Create and apply the deny-all NetworkPolicy manifest.

**Actions:**
- Create `web-deny-all.yaml` manifest
- Apply policy to cluster
- Verify policy creation

**Manifest:** `web-deny-all.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-deny-all
spec:
  podSelector:
    matchLabels:
      app: web
  ingress: []
```

**Command:**
```bash
kubectl apply -f web-deny-all.yaml
```

**Expected Output:**
```
networkpolicy "web-deny-all" created
```

### Task 4: Verify Traffic is Blocked
**Priority:** High
**Status:** pending

Test that traffic is now blocked by the NetworkPolicy.

**Actions:**
- Run new temporary test Pod
- Attempt HTTP request with timeout
- Confirm request times out

**Command:**
```bash
kubectl run --rm -i -t --image=alpine test-$RANDOM -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web
```

**Expected Result:**
```
wget: download timed out
```

## Acceptance Criteria

- [ ] Nginx pod deployed with label `app=web`
- [ ] Service exposed on port 80
- [ ] Initial connectivity verified (before policy)
- [ ] NetworkPolicy `web-deny-all` created successfully
- [ ] Policy targets pods with `app=web` label
- [ ] All traffic to web pod is blocked
- [ ] Connection timeout occurs when accessing web service

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `web-deny-all`
- API Version: `networking.k8s.io/v1`
- Pod Selector: `app=web`
- Ingress Rules: None (empty array)

**How It Works:**
- Targets Pods with `app=web` label
- Missing `spec.ingress` field means no traffic is allowed
- Empty ingress array `[]` blocks all incoming traffic
- Pods without matching labels are unaffected

## Implementation Details

The manifest targets Pods with `app=web` label to police the network. The `spec.ingress` field is empty, therefore not allowing any traffic into the Pod.

**Important Notes:**
- If you create another NetworkPolicy that gives some Pods access to this application (directly or indirectly), this NetworkPolicy will be obsolete
- If there is at least one NetworkPolicy with a rule allowing traffic, it means traffic will be routed to the pod regardless of policies blocking it
- NetworkPolicies are additive - their union is evaluated

## Verification

Verify the policy exists:
```bash
kubectl get networkpolicy
kubectl describe networkpolicy web-deny-all
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod web
kubectl delete service web
kubectl delete networkpolicy web-deny-all
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy API Reference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#networkpolicy-v1-networking-k8s-io)

## Real-World Examples

### Example 1: Isolate Database During Maintenance
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-maintenance-deny-all
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgresql
      role: primary
  ingress: []
```

**Use Case:** Temporarily block all traffic to a database while performing maintenance operations like upgrades, migrations, or backups. Remove the policy when maintenance is complete.

### Example 2: Lock Down Sensitive Application
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payment-service-deny-all
  namespace: finance
spec:
  podSelector:
    matchLabels:
      app: payment-processor
      tier: critical
  ingress: []
```

**Use Case:** Start with complete isolation for a sensitive payment processing service, then selectively whitelist only the specific services that need access.

### Example 3: Quarantine Suspicious Pod
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-suspicious-pod
  namespace: default
spec:
  podSelector:
    matchLabels:
      quarantine: "true"
  ingress: []
  egress: []
```

**Use Case:** Immediately isolate a potentially compromised pod by applying a quarantine label and deny-all policy for both ingress and egress. This prevents lateral movement while you investigate.

## Debugging Tips

**Verify Policy Application:**
```bash
# Check if policy exists
kubectl get networkpolicy

# View policy details
kubectl describe networkpolicy web-deny-all

# Check policy YAML
kubectl get networkpolicy web-deny-all -o yaml

# Verify policy targets correct pods
kubectl get pods -l app=web --show-labels
```

**Test Connectivity:**
```bash
# Test from temporary pod (should timeout)
kubectl run test-connectivity --rm -i -t --image=alpine -- sh
# Inside pod:
wget -qO- --timeout=2 http://web
nc -zv web 80
telnet web 80

# Test with curl (requires curl image)
kubectl run test-curl --rm -i -t --image=curlimages/curl -- curl -m 2 http://web

# Test from specific source pod
kubectl exec -it <source-pod> -- wget -qO- --timeout=2 http://web
```

**Verify Pod Labels:**
```bash
# Check pod labels
kubectl get pods --show-labels

# Check specific pod label
kubectl get pod web -o jsonpath='{.metadata.labels}'

# List all pods with specific label
kubectl get pods -l app=web
```

**Check Service Endpoints:**
```bash
# Verify service exists
kubectl get service web

# Check service endpoints
kubectl get endpoints web

# Describe service
kubectl describe service web
```

**Policy Troubleshooting:**
```bash
# Check if CNI plugin supports NetworkPolicy
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# View CNI plugin logs (example with Calico)
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50

# Check API server for NetworkPolicy support
kubectl api-resources | grep networkpolicy

# Verify API version
kubectl api-versions | grep networking.k8s.io/v1
```

## Common Mistakes

**1. Wrong Pod Selector**
```yaml
# ❌ WRONG: Typo in label name
spec:
  podSelector:
    matchLabels:
      app: webapp  # Pod actually has label "app: web"
  ingress: []
```

**Solution:** Always verify pod labels match exactly:
```bash
kubectl get pods --show-labels
kubectl get pod web -o jsonpath='{.metadata.labels.app}'
```

**2. Forgetting NetworkPolicy is Namespace-Scoped**
```yaml
# ❌ WRONG: Missing namespace in metadata
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-all
  # Missing namespace - defaults to 'default'
```

**Solution:** Always specify the namespace:
```yaml
metadata:
  name: web-deny-all
  namespace: production  # Explicit namespace
```

**3. Assuming Policy Blocks All Pods**
```yaml
# ❌ MISCONCEPTION: This only affects pods with app=web
spec:
  podSelector:
    matchLabels:
      app: web
  ingress: []
```

**Reality:** The policy ONLY affects pods matching the `podSelector`. Other pods remain unaffected.

**4. Not Testing Before and After**
```bash
# ❌ WRONG: Apply policy without testing baseline
kubectl apply -f web-deny-all.yaml

# ✅ CORRECT: Test connectivity before policy
kubectl run test --rm -i -t --image=alpine -- wget -qO- http://web
# Then apply policy
kubectl apply -f web-deny-all.yaml
# Then test again (should fail)
kubectl run test --rm -i -t --image=alpine -- wget -qO- --timeout=2 http://web
```

**5. Confusion with Egress**
```yaml
# ⚠️ WARNING: This only blocks INGRESS
spec:
  podSelector:
    matchLabels:
      app: web
  ingress: []
  # No egress field - egress is NOT blocked
```

**To block both ingress and egress:**
```yaml
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
```

**6. CNI Plugin Not Supporting NetworkPolicy**
```bash
# ❌ PROBLEM: Policy created but not enforced
kubectl apply -f web-deny-all.yaml
# Policy shows as created
kubectl get networkpolicy
# But traffic still flows!
```

**Solution:** Verify your CNI plugin supports NetworkPolicy:
```bash
# Check for supported CNI
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|antrea'

# If using unsupported CNI (like flannel), you need to upgrade
```

**7. Thinking "Deny-All" Means "Block Everything"**
```yaml
# ⚠️ This policy ONLY affects pods with app=web label
# All other pods can still communicate freely
spec:
  podSelector:
    matchLabels:
      app: web
  ingress: []
```

**For namespace-wide deny-all, use empty selector:**
```yaml
spec:
  podSelector: {}  # Matches ALL pods in namespace
  ingress: []
```

## Security Considerations

**Defense-in-Depth:**
- NetworkPolicies are ONE layer of security
- Combine with:
  - **RBAC**: Control API access
  - **Pod Security Standards**: Restrict pod capabilities
  - **Service Mesh**: Add mTLS and L7 policies
  - **Application Authentication**: Don't rely solely on network controls

**What NetworkPolicies Protect Against:**
- ✅ Unauthorized network access to pods
- ✅ Lateral movement within cluster
- ✅ Accidental exposure of services
- ✅ Blast radius of compromised pods

**What NetworkPolicies DON'T Protect Against:**
- ❌ Application-level vulnerabilities (SQL injection, XSS, etc.)
- ❌ Compromised credentials
- ❌ Host-level attacks
- ❌ Supply chain attacks
- ❌ Privilege escalation within containers

**Best Practices for Production:**

**1. Start with Deny-All, Then Whitelist:**
```bash
# Step 1: Apply deny-all policy
kubectl apply -f web-deny-all.yaml

# Step 2: Identify legitimate traffic sources
kubectl logs web | grep "refused connection"

# Step 3: Create whitelist policies for legitimate sources
kubectl apply -f web-allow-frontend.yaml
```

**2. Use Labels Consistently:**
```yaml
# ✅ GOOD: Consistent labeling scheme
labels:
  app: web
  tier: frontend
  environment: production
  team: platform
```

**3. Document Dependencies:**
```yaml
# ✅ GOOD: Document in annotations
metadata:
  name: web-deny-all
  annotations:
    description: "Deny all traffic to web pods as baseline"
    whitelist-policies: "web-allow-frontend, web-allow-loadbalancer"
    owner: "platform-team"
```

**4. Monitor Policy Effects:**
```bash
# Monitor for denied connections
kubectl logs -n kube-system -l k8s-app=calico-node | grep DENY

# Check for policy violations
kubectl get events --field-selector reason=NetworkPolicyViolation
```

**5. Test in Non-Production First:**
```bash
# Apply to dev namespace first
kubectl apply -f web-deny-all.yaml -n development

# Test thoroughly
kubectl run test -n development --rm -i -t --image=alpine -- sh

# Then promote to staging
kubectl apply -f web-deny-all.yaml -n staging

# Finally to production
kubectl apply -f web-deny-all.yaml -n production
```

**6. Have Rollback Plan:**
```bash
# Save policy before changes
kubectl get networkpolicy web-deny-all -o yaml > web-deny-all-backup.yaml

# If issues occur, delete policy quickly
kubectl delete networkpolicy web-deny-all

# Or restore from backup
kubectl apply -f web-deny-all-backup.yaml
```

**Compliance Considerations:**
- Many compliance frameworks (PCI-DSS, HIPAA, SOC2) require network segmentation
- NetworkPolicies help satisfy "principle of least privilege" requirements
- Document policies for audit purposes
- Regularly review and update policies

**Common Attack Scenarios:**

**Scenario 1: Compromised Pod Attempting Lateral Movement**
```
Without NetworkPolicy:
Compromised Pod → ✓ Can access database
                → ✓ Can access API servers
                → ✓ Can scan entire cluster

With Deny-All NetworkPolicy:
Compromised Pod → ✗ Cannot access database
                → ✗ Cannot access other services
                → ✗ Contained to single pod
```

**Scenario 2: Accidental Service Exposure**
```
Without NetworkPolicy:
Debugging Pod → ✓ Can access production database
Test Pod     → ✓ Can access payment service

With Deny-All NetworkPolicy:
Debugging Pod → ✗ Access denied
Test Pod     → ✗ Access denied
Only explicitly whitelisted pods have access
```

## Best Practices

**When to Use Deny-All Policies:**

**✅ Good Use Cases:**
- Starting point for implementing zero-trust networking
- Protecting sensitive services (databases, payment systems)
- Quarantining suspicious pods
- Temporary isolation during maintenance
- Implementing least-privilege access

**❌ Avoid For:**
- System namespaces (kube-system, kube-public)
- Pods that need to accept health checks without explicit allow
- Development environments where rapid iteration is needed
- Services with complex, dynamic access patterns (use namespace-wide deny-all instead)

**Progressive Rollout Strategy:**

**Phase 1: Observation (Week 1)**
```bash
# Deploy policy in "audit mode" (if CNI supports it)
# Monitor logs for what would be blocked
kubectl logs -n kube-system -l k8s-app=calico-node | grep AUDIT
```

**Phase 2: Development (Week 2)**
```bash
# Apply to dev namespace
kubectl apply -f web-deny-all.yaml -n development
# Identify and whitelist legitimate traffic
```

**Phase 3: Staging (Week 3)**
```bash
# Apply to staging with monitoring
kubectl apply -f web-deny-all.yaml -n staging
# Monitor for issues
kubectl get events --watch
```

**Phase 4: Production (Week 4+)**
```bash
# Apply to production during low-traffic period
kubectl apply -f web-deny-all.yaml -n production
# Have team on standby for rollback
```

**Label Management:**
```bash
# Use structured labels
kubectl label pod web app=web tier=frontend env=prod team=platform

# Avoid generic labels
# ❌ kubectl label pod web web=true  # Too generic
# ✅ kubectl label pod web app=web    # Specific and clear
```

**Documentation Template:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-deny-all
  annotations:
    purpose: "Baseline deny-all for web application"
    created-by: "platform-team"
    jira-ticket: "SEC-1234"
    related-policies: "web-allow-frontend, web-allow-monitoring"
    last-reviewed: "2025-01-15"
spec:
  podSelector:
    matchLabels:
      app: web
  ingress: []
```

## Notes

**Key Takeaways:**
- This is the **foundation** for implementing whitelisting strategies
- Always **test before and after** applying policies
- Use **consistent labeling** across your applications
- **Document dependencies** and related policies
- Combine with other security controls for defense-in-depth
- **Monitor** policy effects in production
- Have a **rollback plan** ready

**Next Steps:**
After implementing deny-all policies, proceed to:
1. **NP-02**: Learn to whitelist specific pods
2. **NP-03**: Apply namespace-wide default-deny
3. **NP-11**: Implement egress controls

**Remember:** NetworkPolicies are additive. Once you add an allow policy for specific traffic, the deny-all policy remains but allows the whitelisted traffic through.
