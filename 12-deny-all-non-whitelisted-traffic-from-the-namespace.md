---
id: NP-12
title: Deny All Non-Whitelisted Egress Traffic from a Namespace
type: policy
category: egress
priority: high
status: ready
estimated_time: 15m
dependencies: [NP-00]
tags: [network-policy, egress, default-deny, namespace-wide, dns-blocking]
---

## Overview

Implement a fundamental default-deny egress policy that blocks all outgoing traffic from a namespace by default, including DNS resolution, forcing explicit whitelisting of all egress traffic.

## Objectives

- Create a namespace-wide default-deny egress policy
- Block all outgoing traffic including DNS by default
- Establish foundation for explicit egress whitelisting
- Understand the importance of egress control in zero-trust networks

## Background

This is a fundamental policy that blocks all outgoing (egress) traffic from a namespace by default, including DNS resolution. After deploying this, you can deploy Network Policies that allow specific outgoing traffic.

**Use Cases:**
- Implement default "deny all" egress functionality for namespaces
- Create clear visibility into component dependencies
- Deploy network policies that can be translated to dependency graphs
- Enforce zero-trust networking principles
- Prevent unauthorized data exfiltration

**Best Practice:** This policy will give you a default "deny all" functionality. This way, you can clearly identify which components have dependency on which components and deploy Network Policies that can be translated to dependency graphs between components.

**Important:** Consider applying this manifest to any namespace you deploy workloads to (except `kube-system`).

## Requirements

### Task 1: Understand the Policy
**Priority:** High
**Status:** pending

Review and understand the default-deny egress policy structure.

**Policy Characteristics:**
- Applies to entire namespace
- Blocks all egress traffic
- Includes DNS resolution
- Forces explicit whitelisting
- Foundation for zero-trust networking

### Task 2: Create Default-Deny Egress Policy
**Priority:** High
**Status:** pending

Create and apply the namespace-wide egress deny policy.

**Actions:**
- Create `default-deny-all-egress.yaml` manifest
- Configure to target all pods in namespace
- Apply to default namespace

**Manifest:** `default-deny-all-egress.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: default-deny-all-egress
  namespace: default
spec:
  policyTypes:
  - Egress
  podSelector: {}
  egress: []
```

**Key Configuration:**
- `namespace: default` - Deploy to the default namespace
- `podSelector: {}` - Empty selector matches ALL pods
- `policyTypes: [Egress]` - Only affects egress traffic
- `egress: []` - Empty array blocks all egress traffic

**Important Notes:**
- `podSelector: {}` (empty) matches all pods in the namespace
- Empty `egress` list causes all traffic to be dropped
- This includes DNS resolution
- Pods will be unable to make any outbound connections

**Command:**
```bash
kubectl apply -f default-deny-all-egress.yaml
```

**Expected Output:**
```
networkpolicy "default-deny-all-egress" created
```

### Task 3: Test Egress Blocking
**Priority:** High
**Status:** pending

Verify that all egress traffic is blocked, including DNS.

**Actions:**
- Deploy test pod in the namespace
- Attempt internal service connection
- Attempt external connection
- Verify DNS resolution fails

**Test Commands:**
```bash
# Deploy test pod
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh

# Inside the pod, test internal service
wget -qO- --timeout=2 http://kubernetes.default

# Inside the pod, test external service
wget -qO- --timeout=2 http://www.example.com
```

**Expected Result:**
```
wget: bad address 'kubernetes.default'
wget: bad address 'www.example.com'
```

All egress traffic is blocked, including DNS!

## Acceptance Criteria

- [ ] NetworkPolicy `default-deny-all-egress` created successfully
- [ ] Policy deployed to default namespace
- [ ] Policy uses empty podSelector (matches all pods)
- [ ] Policy specifies Egress policyType
- [ ] Empty egress array blocks all traffic
- [ ] DNS resolution blocked
- [ ] Internal service connections blocked
- [ ] External connections blocked
- [ ] Policy provides foundation for whitelisting

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `default-deny-all-egress`
- Namespace: `default`
- Pod Selector: `{}` (all pods)
- Policy Types: Egress
- Egress Rules: None (empty array)

**How It Works:**
- Empty `podSelector: {}` matches every pod in the namespace
- `policyTypes: [Egress]` enforces egress policy
- Empty `egress: []` array blocks all outbound traffic
- No exceptions - even DNS is blocked
- Creates foundation for explicit whitelisting

**Policy Scope:**
```yaml
podSelector: {}  # Matches ALL pods
egress: []       # Allows NO traffic
```

**Effect:**
```
Pod → Any Destination = ✗ BLOCKED
Pod → DNS Server = ✗ BLOCKED
Pod → Internal Service = ✗ BLOCKED
Pod → External IP = ✗ BLOCKED
```

## Implementation Details

**Understanding Default-Deny Egress:**

**Complete Lockdown:**
```yaml
spec:
  policyTypes:
  - Egress
  podSelector: {}  # All pods in namespace
  egress: []       # No traffic allowed
```

**Why This Is Important:**
- Forces explicit documentation of dependencies
- Prevents unauthorized egress traffic
- Enables dependency mapping
- Implements zero-trust principles
- Provides clear audit trail

**Namespace Selection Best Practices:**
```yaml
# Apply to specific namespace
metadata:
  name: default-deny-all-egress
  namespace: default  # Change this for each namespace

# DO NOT apply to:
# - kube-system (system components need egress)
# - Monitoring namespaces (metrics collection needs egress)
# - Ingress controller namespaces
```

**Building on This Foundation:**

After applying this policy, create additional policies to allow specific traffic:

**Example: Allow DNS**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
```

**Example: Allow Specific Service Access**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-allow-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - port: 8080
```

**Example: Allow External API Access**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-allow-external-api
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32  # Block metadata service
    ports:
    - port: 443
      protocol: TCP
```

**Policy Interaction:**
- NetworkPolicies are additive
- Multiple policies are OR'ed together
- Default-deny + specific allow = whitelisting
- Each component gets its own allow policy

## Verification

Check policy and test effectiveness:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy default-deny-all-egress

# Check which pods are affected
kubectl get pods --all-namespaces

# Test from any pod in the namespace
kubectl run test --rm -i -t --image=alpine -- sh
# Inside:
ping 8.8.8.8  # Should fail
nslookup google.com  # Should fail
wget http://kubernetes.default  # Should fail

# View all network policies in namespace
kubectl get networkpolicy -n default
```

## Cleanup

### Task: Remove Policy
Remove the default-deny egress policy:

```bash
kubectl delete networkpolicy default-deny-all-egress
```

**Warning:** Only remove this policy if you're certain no other policies depend on it for security.

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Default Deny Egress](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-egress-traffic)
- [Zero Trust Networking](https://kubernetes.io/blog/2021/04/05/network-policies-conformance-cni/)

## Notes

**Best Practices:**
- Apply to all workload namespaces (except system namespaces)
- Create this policy first, then add allow policies
- Document all egress requirements before deployment
- Test thoroughly in non-production environments
- Monitor for blocked legitimate traffic

**Namespace Application Strategy:**
```bash
# Apply to multiple namespaces
for ns in production staging development; do
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all-egress
  namespace: $ns
spec:
  policyTypes:
  - Egress
  podSelector: {}
  egress: []
EOF
done
```

**Common Patterns After Default-Deny:**

**Pattern 1: DNS for All Pods**
```yaml
# Allow DNS for all pods in namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-access
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
```

**Pattern 2: Internal Services Only**
```yaml
# Allow internal cluster services only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal-only
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}  # All pods in same namespace
  - to:
    - namespaceSelector: {}  # All pods in all namespaces
```

**Pattern 3: Specific External Services**
```yaml
# Allow only specific external IPs
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-specific-external
spec:
  podSelector:
    matchLabels:
      app: api-client
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24  # Specific external service
    ports:
    - port: 443
```

**Debugging Tips:**
```bash
# Check if policy is applied
kubectl get networkpolicy -n default

# View policy details
kubectl describe networkpolicy default-deny-all-egress

# Test egress from specific pod
kubectl exec -it <pod-name> -- wget -qO- --timeout=2 http://google.com

# Check DNS resolution
kubectl exec -it <pod-name> -- nslookup kubernetes.default

# View all policies affecting a pod
kubectl get networkpolicy -n default -o yaml
```

**Common Mistakes:**
- Applying to kube-system namespace (breaks cluster)
- Not allowing DNS in follow-up policies
- Forgetting about health checks and monitoring
- Not testing before production
- Blocking legitimate inter-service communication

**Exceptions and Special Cases:**

**DO NOT Apply To:**
- `kube-system` namespace (system pods need egress)
- `kube-public` namespace
- Monitoring namespaces (Prometheus, Grafana, etc.)
- Logging namespaces (Fluentd, Logstash, etc.)
- Ingress controller namespaces

**Considerations:**
- Health checks may need egress
- Monitoring agents need to reach collection endpoints
- Logging agents need to send logs
- Init containers may need external resources
- Application startup may require external configuration

**Progressive Rollout:**
```bash
# 1. Start with audit/monitoring only
#    Deploy but don't enforce - log violations

# 2. Apply to dev namespace first
kubectl apply -f default-deny-all-egress.yaml -n development

# 3. Identify required egress (check logs)
kubectl logs <pod> | grep "connection refused\|timeout"

# 4. Create allow policies
kubectl apply -f allow-dns.yaml -n development
kubectl apply -f allow-backend.yaml -n development

# 5. Test thoroughly
# Run integration tests

# 6. Roll out to staging, then production
kubectl apply -f default-deny-all-egress.yaml -n staging
kubectl apply -f default-deny-all-egress.yaml -n production
```

**Security Considerations:**
- This is defense-in-depth, not a silver bullet
- Combine with Pod Security Policies/Standards
- Use alongside RBAC and authentication
- Monitor for policy violations
- Regular security audits
- Document all allow policies and their justification

**Monitoring and Alerting:**
```bash
# Monitor for blocked connections (if your CNI supports it)
# Example with Cilium:
cilium monitor --type drop

# Example with Calico:
calicoctl get globalnetworkpolicy -o yaml

# Check for policy violations in logs
kubectl logs -n kube-system -l k8s-app=calico-node | grep "denied"
```

**Documentation Template:**
```yaml
# Document why egress is needed
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-allow-database
  namespace: production
  annotations:
    description: "Allow frontend to connect to PostgreSQL"
    jira-ticket: "SEC-1234"
    approved-by: "security-team"
    approved-date: "2025-01-15"
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
    ports:
    - port: 5432
```

This policy is essential for implementing zero-trust networking and maintaining clear visibility into service dependencies and data flows within your Kubernetes cluster.
