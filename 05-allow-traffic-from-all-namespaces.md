---
id: NP-05
title: Allow Traffic from All Namespaces
type: policy
category: namespaces
priority: medium
status: ready
estimated_time: 15m
dependencies: [NP-00]
tags: [network-policy, cross-namespace, shared-services, allow]
---

## Overview

Create a NetworkPolicy that allows traffic from all pods in all namespaces to a particular application, enabling cross-namespace access to shared services.

## Objectives

- Enable cross-namespace access to specific applications
- Allow traffic from all namespaces to shared services
- Override restrictive namespace policies for specific workloads
- Support common services accessible cluster-wide

## Background

This NetworkPolicy allows traffic from all pods in all namespaces to reach a particular application. This pattern is useful for shared infrastructure services that need to be accessible from multiple namespaces.

**Use Cases:**
- Common service or database used by deployments in different namespaces
- Shared monitoring or logging endpoints
- Central authentication services
- Internal API gateways serving multiple teams

**Important:** You do not need this policy unless there is already a NetworkPolicy [blocking traffic to the application](01-deny-all-traffic-to-an-application.md) or a NetworkPolicy [blocking non-whitelisted traffic to all pods in the namespace](03-deny-all-non-whitelisted-traffic-in-the-namespace.md).

![Diagram of ALLOW traffic to an application from all namespaces policy](img/5.gif)

## Requirements

### Task 1: Deploy Shared Service
**Priority:** High
**Status:** pending

Start a web service on default namespace.

**Actions:**
- Deploy nginx pod with label `app=web` in default namespace
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --namespace=default --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Create Allow-All-Namespaces Policy
**Priority:** High
**Status:** pending

Create and apply NetworkPolicy that allows traffic from all namespaces.

**Actions:**
- Create `web-allow-all-namespaces.yaml` manifest
- Configure pod selector for target application
- Configure ingress rule with empty namespaceSelector
- Apply to cluster

**Manifest:** `web-allow-all-namespaces.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  namespace: default
  name: web-allow-all-namespaces
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - namespaceSelector: {}
```

**Key Configuration Points:**
- Applies policy only to `app:web` pods in `default` namespace
- `namespaceSelector: {}` selects all pods in all namespaces
- By default, omitting `namespaceSelector` would only allow traffic from the same namespace

**Alternative Syntax:**

Dropping all selectors from `spec.ingress.from` has the same effect:
```yaml
ingress:
  - from:
```

However, the explicit `namespaceSelector: {}` form is preferred for clarity.

**Command:**
```bash
kubectl apply -f web-allow-all-namespaces.yaml
```

**Expected Output:**
```
networkpolicy "web-allow-all-namespaces" created
```

### Task 3: Create Test Namespace
**Priority:** High
**Status:** pending

Create a secondary namespace for testing cross-namespace access.

**Actions:**
- Create namespace called `secondary`
- Verify namespace exists

**Command:**
```bash
kubectl create namespace secondary
```

### Task 4: Test Cross-Namespace Access
**Priority:** High
**Status:** pending

Verify that traffic from other namespaces is allowed.

**Actions:**
- Run test pod in secondary namespace
- Attempt connection to web service in default namespace
- Confirm connection succeeds

**Commands:**
```bash
kubectl run test-$RANDOM --namespace=secondary --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
```

Traffic from secondary namespace works!

## Acceptance Criteria

- [ ] Web service deployed in default namespace with label `app=web`
- [ ] Service exposed on port 80
- [ ] NetworkPolicy `web-allow-all-namespaces` created
- [ ] Policy targets only pods with `app=web` label
- [ ] Empty namespaceSelector configured
- [ ] Test namespace `secondary` created
- [ ] Traffic from secondary namespace is allowed
- [ ] Traffic from default namespace also works
- [ ] Cross-namespace communication verified

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `web-allow-all-namespaces`
- API Version: `networking.k8s.io/v1`
- Namespace: `default`
- Pod Selector: `app=web`
- Ingress Source: All pods in all namespaces

**How It Works:**
- `podSelector` targets specific application pods
- `namespaceSelector: {}` allows traffic from all namespaces
- Empty namespace selector matches all namespaces
- Pods matching the source criteria can connect

**Selector Combinations:**
```yaml
# Allow from all pods in all namespaces
namespaceSelector: {}

# Allow from all pods in same namespace only (default)
# (no namespaceSelector specified)

# Allow from specific namespace
namespaceSelector:
  matchLabels:
    name: production

# Allow from specific pods in all namespaces
namespaceSelector: {}
podSelector:
  matchLabels:
    role: frontend
```

## Implementation Details

The `namespaceSelector: {}` is the critical component:

**Without namespaceSelector:**
```yaml
ingress:
- from:
  - podSelector: {}
# Allows only from same namespace
```

**With empty namespaceSelector:**
```yaml
ingress:
- from:
  - namespaceSelector: {}
# Allows from all namespaces
```

**Combining both selectors:**
```yaml
ingress:
- from:
  - podSelector: {}
    namespaceSelector: {}
# Allows from all pods in all namespaces (same as namespaceSelector alone)
```

## Verification

Check policy status:
```bash
kubectl get networkpolicy -n default
kubectl describe networkpolicy web-allow-all-namespaces -n default
```

Test from multiple namespaces:
```bash
# Test from default namespace
kubectl run test-$RANDOM --namespace=default --rm -i -t --image=alpine -- sh

# Test from another namespace
kubectl run test-$RANDOM --namespace=secondary --rm -i -t --image=alpine -- sh
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod web -n default
kubectl delete service web -n default
kubectl delete networkpolicy web-allow-all-namespaces -n default
kubectl delete namespace secondary
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Namespace Selector Documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Deny All Traffic Pattern](01-deny-all-traffic-to-an-application.md)
- [Namespace Default Deny Pattern](03-deny-all-non-whitelisted-traffic-in-the-namespace.md)

## Notes

**Best Practices:**
- Use this pattern sparingly - prefer restrictive policies
- Document why cross-namespace access is needed
- Consider using service mesh for more sophisticated routing
- Monitor cross-namespace traffic for unexpected patterns

**Security Considerations:**
- This policy essentially makes the application "public" within the cluster
- All namespaces include user workloads and system namespaces
- Consider whether specific namespace selection would be more appropriate
- Combine with authentication/authorization at application level

**Common Use Cases:**
- Central logging aggregators (e.g., Elasticsearch)
- Shared databases (with proper authentication)
- Monitoring endpoints (e.g., Prometheus)
- Service mesh control planes
- DNS servers
- Internal API gateways

This policy is useful for shared infrastructure but should be applied judiciously with proper security controls at the application layer.
