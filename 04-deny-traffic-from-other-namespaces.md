---
id: NP-04
title: Deny All Traffic from Other Namespaces
type: policy
category: namespaces
priority: high
status: ready
estimated_time: 15m
dependencies: [NP-00]
tags: [network-policy, namespace-isolation, multi-tenancy, security]
---

## Overview

Configure a NetworkPolicy to deny all traffic from other namespaces while allowing all traffic within the same namespace, implementing namespace-level isolation.

## Objectives

- Block all cross-namespace traffic
- Allow intra-namespace communication
- Implement namespace isolation for multi-tenancy
- Prevent accidental cross-environment communication

## Background

This policy denies all traffic from other namespaces while allowing all traffic coming from the same namespace where the pod is deployed. This is also known as "LIMIT access to the current namespace".

**Use Cases:**
- Prevent deployments in `test` namespace from accidentally sending traffic to services or databases in `prod` namespace
- Host applications from different customers in separate Kubernetes namespaces and block traffic coming from outside a namespace
- Implement multi-tenant cluster architecture
- Create environment isolation (dev, staging, prod)

![Diagram of DENY all traffic from other namespaces policy](img/4.gif)

## Requirements

### Task 1: Deploy Test Application
**Priority:** High
**Status:** pending

Start a web service in the default namespace.

**Actions:**
- Deploy nginx pod with label `app=web` in default namespace
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --namespace=default --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Create Namespace Isolation Policy
**Priority:** High
**Status:** pending

Create and apply NetworkPolicy that allows only same-namespace traffic.

**Actions:**
- Create `deny-from-other-namespaces.yaml` manifest
- Configure empty pod selector (applies to all pods)
- Configure ingress rule for same-namespace only
- Apply to target namespace

**Manifest:** `deny-from-other-namespaces.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  namespace: default
  name: deny-from-other-namespaces
spec:
  podSelector:
    matchLabels:
  ingress:
  - from:
    - podSelector: {}
```

**Key Configuration Points:**
- `namespace: default` - Deploys it to the `default` namespace
- `spec.podSelector.matchLabels` - Empty selector applies policy to ALL pods in namespace
- `spec.ingress.from.podSelector: {}` - Empty selector allows traffic from ALL pods in the same namespace only
- No `namespaceSelector` specified - restricts traffic to current namespace only

**Command:**
```bash
kubectl apply -f deny-from-other-namespaces.yaml
```

**Expected Output:**
```
networkpolicy "deny-from-other-namespaces" created
```

### Task 3: Test Cross-Namespace Blocking
**Priority:** High
**Status:** pending

Verify that traffic from other namespaces is blocked.

**Actions:**
- Create test namespace `foo`
- Run test pod in `foo` namespace
- Attempt connection to web service in default namespace
- Confirm connection is blocked

**Commands:**
```bash
kubectl create namespace foo
kubectl run test-$RANDOM --namespace=foo --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```
wget: download timed out
```

Traffic from `foo` namespace is blocked!

### Task 4: Test Same-Namespace Access
**Priority:** High
**Status:** pending

Verify that traffic within the same namespace is allowed.

**Actions:**
- Run test pod in default namespace
- Attempt connection to web service
- Confirm connection succeeds

**Commands:**
```bash
kubectl run test-$RANDOM --namespace=default --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
```

Traffic within default namespace works fine!

## Acceptance Criteria

- [ ] Web service deployed in default namespace
- [ ] NetworkPolicy `deny-from-other-namespaces` created
- [ ] Policy applies to all pods in namespace (empty podSelector)
- [ ] Traffic from other namespaces is blocked (timeout)
- [ ] Traffic within same namespace is allowed (successful response)
- [ ] Test namespace created for verification
- [ ] Cross-namespace traffic blocked consistently

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `deny-from-other-namespaces`
- API Version: `networking.k8s.io/v1`
- Scope: All pods in specified namespace
- Pod Selector: Empty (matches all pods)
- Ingress Source: All pods in same namespace only

**How It Works:**
- Empty `podSelector` applies policy to all pods in the namespace
- `ingress.from.podSelector: {}` allows traffic from all pods
- Absence of `namespaceSelector` restricts source to current namespace
- Traffic from other namespaces is implicitly denied

**Selector Behavior:**
- `podSelector: {}` alone = same namespace only
- `podSelector: {}` + `namespaceSelector: {}` = all namespaces
- No selector = deny all

## Implementation Details

This policy leverages the default namespace-scoping behavior of podSelector:

**Key Insight:** When you specify a `podSelector` without a `namespaceSelector` in an ingress rule, it only matches pods in the same namespace as the NetworkPolicy.

**Equivalent Explicit Form:**
```yaml
ingress:
- from:
  - podSelector: {}
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: default
```

However, omitting `namespaceSelector` is simpler and more maintainable.

## Verification

Check policy status:
```bash
kubectl get networkpolicy -n default
kubectl describe networkpolicy deny-from-other-namespaces -n default
```

List namespaces:
```bash
kubectl get namespaces
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod web -n default
kubectl delete service web -n default
kubectl delete networkpolicy deny-from-other-namespaces -n default
kubectl delete namespace foo
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Namespace Isolation Patterns](https://kubernetes.io/docs/concepts/services-networking/network-policies/#targeting-a-namespace-by-its-name)
- [Multi-tenancy Best Practices](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

## Notes

**Best Practices:**
- Apply this policy to all production namespaces
- Use namespace labels to organize environments
- Consider combining with PodSecurityPolicies for defense in depth
- Document namespace communication requirements

**Common Patterns:**
- Environment Isolation: Separate dev, staging, prod namespaces
- Team Isolation: Separate namespaces per team or project
- Customer Isolation: Separate namespaces per customer (multi-tenancy)

**Important Considerations:**
- This policy allows ALL pods within the namespace to communicate
- Consider combining with pod-level policies for finer control
- Remember to allow traffic from ingress controllers if needed
- System namespaces (kube-system) may need special handling

This policy is essential for multi-tenant Kubernetes clusters and environment isolation strategies.
