---
id: NP-07
title: Allow Traffic from Some Pods in Another Namespace
type: policy
category: namespaces
priority: high
status: ready
estimated_time: 25m
dependencies: [NP-00]
tags: [network-policy, namespace-selector, pod-selector, intersection, kubernetes-v1.11]
---

## Overview

Implement a NetworkPolicy that uses the AND operation to combine podSelector and namespaceSelector, allowing traffic only from specific pods in specific namespaces.

## Objectives

- Use combined podSelector and namespaceSelector with AND operation
- Allow traffic only from specific pods in labeled namespaces
- Understand the difference between AND and OR conditions in NetworkPolicy
- Restrict access to monitoring pods in operations namespaces

## Background

Since Kubernetes v1.11, it is possible to combine `podSelector` and `namespaceSelector` with an AND (intersection) operation. This enables fine-grained control over which pods in which namespaces can access your services.

**Use Cases:**
- Allow only monitoring pods from operations namespaces to scrape metrics
- Restrict database access to specific application pods in production namespaces
- Enable debugging tools in specific namespaces to access target services
- Implement fine-grained multi-tenant access control

**Important Notes:**
- This feature is available on Kubernetes v1.11 or after
- Most networking plugins do not yet support this feature
- Make sure to test this policy after deployment to verify it works correctly

## Requirements

### Task 1: Deploy Web Server
**Priority:** High
**Status:** pending

Run a web application in the default namespace.

**Actions:**
- Deploy nginx pod with label `app=web`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Create and Label Target Namespace
**Priority:** High
**Status:** pending

Create a namespace with appropriate labels for testing.

**Actions:**
- Create `other` namespace
- Label namespace with `team=operations`
- Verify namespace label

**Commands:**
```bash
kubectl create namespace other
kubectl label namespace/other team=operations
```

**Verification:**
```bash
kubectl get namespace other --show-labels
```

### Task 3: Create Combined Selector Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that uses AND operation to restrict traffic to specific pods in specific namespaces.

**Actions:**
- Create `web-allow-all-ns-monitoring.yaml` manifest
- Configure combined namespace and pod selectors
- Apply policy to cluster

**Manifest:** `web-allow-all-ns-monitoring.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-all-ns-monitoring
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
    - from:
      - namespaceSelector:     # chooses all pods in namespaces labelled with team=operations
          matchLabels:
            team: operations
        podSelector:           # chooses pods with type=monitoring
          matchLabels:
            type: monitoring
```

**Key Configuration:**
- Targets pods with `app: web` label
- Uses AND condition: namespace must have `team=operations` AND pod must have `type=monitoring`
- Both conditions must be true for traffic to be allowed

**Command:**
```bash
kubectl apply -f web-allow-all-ns-monitoring.yaml
```

**Expected Output:**
```
networkpolicy.networking.k8s.io/web-allow-all-ns-monitoring created
```

### Task 4: Test from Default Namespace Without Labels (Blocked)
**Priority:** High
**Status:** pending

Verify traffic from default namespace without proper labels is blocked.

**Actions:**
- Run test pod in default namespace without labels
- Attempt connection to web service
- Confirm connection is blocked

**Commands:**
```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```
wget: download timed out
```

Traffic is blocked (namespace is not labeled `team=operations`)!

### Task 5: Test from Default Namespace With Monitoring Label (Blocked)
**Priority:** High
**Status:** pending

Verify that even with pod label, traffic is blocked from wrong namespace.

**Actions:**
- Run test pod with `type=monitoring` label in default namespace
- Attempt connection to web service
- Confirm connection is still blocked

**Commands:**
```bash
kubectl run test-$RANDOM --labels="type=monitoring" --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```
wget: download timed out
```

Traffic is blocked (default namespace doesn't have `team=operations` label)!

### Task 6: Test from Other Namespace Without Labels (Blocked)
**Priority:** High
**Status:** pending

Verify traffic from other namespace without pod label is blocked.

**Actions:**
- Run test pod in other namespace without pod labels
- Attempt connection to web service
- Confirm connection is blocked

**Commands:**
```bash
kubectl run test-$RANDOM --namespace=other --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```
wget: download timed out
```

Traffic is blocked (pod doesn't have `type=monitoring` label)!

### Task 7: Test from Other Namespace With Monitoring Label (Allowed)
**Priority:** High
**Status:** pending

Verify traffic is allowed when both conditions are met.

**Actions:**
- Run test pod with `type=monitoring` label in other namespace (labeled `team=operations`)
- Attempt connection to web service
- Confirm connection succeeds

**Commands:**
```bash
kubectl run test-$RANDOM --namespace=other --labels="type=monitoring" --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
...
```

Traffic is allowed (both conditions are met)!

## Acceptance Criteria

- [ ] Web service deployed in default namespace
- [ ] Other namespace created with label `team=operations`
- [ ] NetworkPolicy `web-allow-all-ns-monitoring` created successfully
- [ ] Policy uses combined podSelector and namespaceSelector (AND operation)
- [ ] Traffic from default namespace is blocked (wrong namespace)
- [ ] Traffic from default namespace with monitoring label is blocked (wrong namespace)
- [ ] Traffic from other namespace without monitoring label is blocked (wrong pod)
- [ ] Traffic from other namespace with monitoring label is allowed (both conditions met)

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `web-allow-all-ns-monitoring`
- Namespace: `default`
- Pod Selector: `app=web`
- Ingress Source: Pods with `type=monitoring` in namespaces with `team=operations`

**How It Works:**
- The policy uses AND (intersection) operation
- Namespace must have label `team=operations`
- AND pod must have label `type=monitoring`
- Both conditions are required - missing either one blocks traffic
- The selectors are at the same indentation level (same list item in `from`)

**AND vs OR Conditions:**

**OR Condition (separate list items):**
```yaml
ingress:
  - from:
    - namespaceSelector:     # OR condition
        matchLabels:
          team: operations
    - podSelector:           # These are separate items
        matchLabels:
          type: monitoring
```
This allows traffic from:
- ANY pod in namespaces with `team=operations` OR
- ANY pod with `type=monitoring` in the same namespace

**AND Condition (same list item):**
```yaml
ingress:
  - from:
    - namespaceSelector:     # AND condition
        matchLabels:
          team: operations
      podSelector:           # These are combined
        matchLabels:
          type: monitoring
```
This allows traffic from:
- Pods with `type=monitoring` in namespaces with `team=operations`
- Both conditions MUST be true

## Implementation Details

**Understanding the Intersection:**
- When `namespaceSelector` and `podSelector` are in the same `from` entry, they are ANDed together
- This creates an intersection: pods must match BOTH selectors
- The namespace is selected first, then pods within that namespace are filtered
- This enables precise access control across namespace boundaries

**YAML Structure Matters:**
```yaml
# Same list item (AND)
- from:
  - namespaceSelector: {...}
    podSelector: {...}

# Different list items (OR)
- from:
  - namespaceSelector: {...}
  - podSelector: {...}
```

**Real-World Examples:**
```yaml
# Allow only monitoring pods from ops namespaces
- from:
  - namespaceSelector:
      matchLabels:
        team: operations
    podSelector:
      matchLabels:
        role: monitoring

# Allow debug pods from troubleshooting namespace
- from:
  - namespaceSelector:
      matchLabels:
        purpose: troubleshooting
    podSelector:
      matchLabels:
        tool: debugger

# Allow specific app pods from production namespaces
- from:
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: frontend
```

## Verification

Check policy configuration:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy web-allow-all-ns-monitoring

# View namespace labels
kubectl get namespaces --show-labels

# Check specific namespace
kubectl describe namespace other
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete networkpolicy web-allow-all-ns-monitoring
kubectl delete namespace other
kubectl delete pod web
kubectl delete service web
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy v1.11 Release Notes](https://kubernetes.io/blog/2018/06/27/kubernetes-1.11-release-announcement/)
- [Label Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)

## Notes

**Important Considerations:**
- This feature requires Kubernetes v1.11+
- Not all CNI plugins support this feature - verify with your network provider
- Always test policies after deployment to ensure they work as expected
- The AND operation provides fine-grained control but requires careful label management

**Best Practices:**
- Document your namespace labeling scheme
- Use consistent label naming across namespaces
- Test both positive and negative cases (allowed and blocked traffic)
- Consider using label namespaces (e.g., `team.company.com/name`)
- Monitor policy effectiveness with network policy logs

**Common Mistakes:**
- Confusing AND vs OR syntax (indentation matters!)
- Forgetting to label namespaces
- Not testing with all combinations of labels
- Assuming the feature is supported by all CNI plugins

**Debugging Tips:**
```bash
# Check if namespace has correct labels
kubectl get namespace <name> --show-labels

# Check if pod has correct labels
kubectl get pods --show-labels -n <namespace>

# Describe NetworkPolicy to see what it's selecting
kubectl describe networkpolicy <name>

# Check CNI plugin version and features
kubectl get pods -n kube-system
```

This advanced pattern is essential for implementing sophisticated multi-tenant access control in Kubernetes clusters where namespace and pod-level isolation is required.
