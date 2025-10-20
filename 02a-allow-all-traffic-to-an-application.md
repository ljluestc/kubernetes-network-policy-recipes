---
id: NP-02A
title: Allow All Traffic to an Application
type: policy
category: basics
priority: medium
status: ready
estimated_time: 10m
dependencies: [NP-00, NP-01]
tags: [network-policy, allow-all, ingress, override, permissive]
---

## Overview

Create a NetworkPolicy that explicitly allows all traffic to an application, overriding any restrictive policies and enabling access from all pods in all namespaces.

## Objectives

- Override deny-all policies with an explicit allow-all rule
- Enable unrestricted access to an application from all namespaces
- Understand how NetworkPolicy rules combine additively
- Demonstrate policy precedence and override behavior

## Background

After applying a [deny-all](01-deny-all-traffic-to-an-application.md) policy that blocks all non-whitelisted traffic to an application, this policy allows access from all pods in the current namespace and other namespaces.

**Important:** Applying this policy makes any other policies restricting traffic to the pod void, allowing all traffic from any namespace. NetworkPolicies are additive - if at least one policy allows traffic, it will flow regardless of other blocking policies.

**Use Cases:**
- Temporarily open access to a service for debugging
- Override restrictive policies for shared services
- Create exceptions for common infrastructure components
- Explicitly document that a service should be accessible from anywhere

## Requirements

### Task 1: Deploy Test Application
**Priority:** High
**Status:** pending

Start a web application to demonstrate the policy.

**Actions:**
- Deploy nginx pod with label `app=web`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Create and Apply Allow-All Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy manifest that allows all traffic.

**Actions:**
- Create `web-allow-all.yaml` manifest
- Configure empty ingress rule to allow all traffic
- Apply policy to cluster

**Manifest:** `web-allow-all.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-all
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - {}
```

**Key Points:**
- `namespace: default` deploys this policy to the `default` namespace
- `podSelector` applies the ingress rule to pods with `app: web` label
- Empty ingress rule `{}` allows traffic from all pods in all namespaces
- Equivalent to explicitly specifying:
  ```yaml
  - from:
    - podSelector: {}
      namespaceSelector: {}
  ```

**Command:**
```bash
kubectl apply -f web-allow-all.yaml
```

**Expected Output:**
```
networkpolicy "web-allow-all" created
```

### Task 3: Test with Deny-All Policy (Optional)
**Priority:** Medium
**Status:** pending

Optionally apply the [`web-deny-all` policy](01-deny-all-traffic-to-an-application.md) to validate that `web-allow-all` overrides it.

**Actions:**
- Apply web-deny-all policy
- Verify web-allow-all takes precedence
- Traffic should still be allowed

**Command:**
```bash
kubectl apply -f web-deny-all.yaml
```

### Task 4: Verify Traffic is Allowed
**Priority:** High
**Status:** pending

Test that traffic flows freely to the application.

**Actions:**
- Run temporary test pod
- Make HTTP request to web service
- Confirm successful response

**Command:**
```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web
```

**Expected Result:**
```html
<!DOCTYPE html>
<html><head>
...
```

Traffic is allowed!

## Acceptance Criteria

- [ ] Web pod deployed with label `app=web`
- [ ] Service exposed on port 80
- [ ] NetworkPolicy `web-allow-all` created successfully
- [ ] Policy targets pods with `app=web` label
- [ ] Empty ingress rule configured correctly
- [ ] Traffic from any pod in any namespace is allowed
- [ ] Policy overrides any existing deny policies
- [ ] HTTP requests succeed from test pods

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `web-allow-all`
- API Version: `networking.k8s.io/v1`
- Namespace: `default`
- Pod Selector: `app=web`
- Ingress Rules: Empty rule `{}`

**How It Works:**
- Empty ingress rule `{}` matches all sources
- Allows traffic from all pods in current namespace
- Allows traffic from all pods in all other namespaces
- NetworkPolicies are additive - allow rules take precedence
- If any policy allows traffic, it flows regardless of deny policies

**Policy Precedence:**
- NetworkPolicies combine additively (union of all rules)
- An allow rule in any policy enables the traffic
- Cannot create explicit "deny" rules
- Default behavior without policies: allow all
- Default behavior with policies: deny all except allowed

## Implementation Details

The empty ingress rule is the key to this policy:

```yaml
ingress:
- {}
```

This is equivalent to:
```yaml
ingress:
- from:
  - podSelector: {}
    namespaceSelector: {}
```

Both forms select all pods from all namespaces, but the empty form `{}` is more concise.

## Verification

Check policy status:
```bash
kubectl get networkpolicy
kubectl describe networkpolicy web-allow-all
```

Test from different namespaces:
```bash
kubectl create namespace test-ns
kubectl run test-$RANDOM --namespace=test-ns --rm -i -t --image=alpine -- sh
# wget -qO- http://web.default
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod,service web
kubectl delete networkpolicy web-allow-all web-deny-all
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy Deny-All Pattern](01-deny-all-traffic-to-an-application.md)
- [Network Policy Best Practices](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-policies)

## Notes

Use this policy carefully in production environments. While it can be useful for shared services or debugging, it effectively disables network segmentation for the target application. Consider whether a more restrictive policy with explicit namespace or pod selectors would be more appropriate.

This pattern demonstrates the additive nature of NetworkPolicies - once any policy allows traffic, that traffic will flow regardless of other policies.
