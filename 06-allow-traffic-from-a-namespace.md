---
id: NP-06
title: Allow Traffic from a Specific Namespace
type: policy
category: namespaces
priority: high
status: ready
estimated_time: 20m
dependencies: [NP-00]
tags: [network-policy, namespace-selector, cross-namespace, label-based]
---

## Overview

Create a NetworkPolicy that allows traffic from all pods in a specific namespace selected by labels, enabling selective cross-namespace communication.

## Objectives

- Allow traffic from specific namespaces using label selectors
- Implement label-based namespace access control
- Restrict database access to production namespaces only
- Enable monitoring tools to scrape metrics across namespaces

## Background

This policy is similar to [allowing traffic from all namespaces](05-allow-traffic-from-all-namespaces.md) but demonstrates how to choose particular namespaces using label selectors.

**Use Cases:**
- Restrict traffic to a production database only to namespaces where production workloads are deployed
- Enable monitoring tools deployed to a particular namespace to scrape metrics from the current namespace
- Allow specific teams' namespaces to access shared services
- Implement environment-based access control (prod-to-prod, dev-to-dev)

![Diagram of ALLOW all traffic from a namespace policy](img/6.gif)

## Requirements

### Task 1: Deploy Web Server
**Priority:** High
**Status:** pending

Run a web server in the `default` namespace.

**Actions:**
- Deploy nginx pod with label `app=web`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Create and Label Namespaces
**Priority:** High
**Status:** pending

Create test namespaces with appropriate labels.

**Actions:**
- Create `dev` namespace with label `purpose=testing`
- Create `prod` namespace with label `purpose=production`
- Verify namespace labels

**Namespace Setup:**
- `default`: Where the API is deployed (installed by Kubernetes)
- `prod`: Production workloads run here (label: `purpose=production`)
- `dev`: Dev/test area (label: `purpose=testing`)

**Commands:**
```bash
# Create dev namespace
kubectl create namespace dev
kubectl label namespace/dev purpose=testing

# Create prod namespace
kubectl create namespace prod
kubectl label namespace/prod purpose=production
```

**Verify labels:**
```bash
kubectl get namespaces --show-labels
```

### Task 3: Create Namespace-Selective Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that restricts traffic to pods from production namespace only.

**Actions:**
- Create `web-allow-prod.yaml` manifest
- Configure namespace selector with label matching
- Apply policy to cluster

**Manifest:** `web-allow-prod.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-prod
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: production
```

**Key Configuration:**
- Targets pods with `app: web` label
- Allows traffic only from namespaces with `purpose=production` label
- Uses `matchLabels` to select specific namespaces

**Command:**
```bash
kubectl apply -f web-allow-prod.yaml
```

**Expected Output:**
```
networkpolicy "web-allow-prod" created
```

### Task 4: Test Traffic from Dev Namespace (Blocked)
**Priority:** High
**Status:** pending

Verify that traffic from dev namespace is blocked.

**Actions:**
- Run test pod in dev namespace
- Attempt connection to web service in default namespace
- Confirm connection is blocked

**Commands:**
```bash
kubectl run test-$RANDOM --namespace=dev --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://web.default
```

**Expected Result:**
```
wget: download timed out
```

Traffic is blocked from dev namespace!

### Task 5: Test Traffic from Prod Namespace (Allowed)
**Priority:** High
**Status:** pending

Verify that traffic from prod namespace is allowed.

**Actions:**
- Run test pod in prod namespace
- Attempt connection to web service in default namespace
- Confirm connection succeeds

**Commands:**
```bash
kubectl run test-$RANDOM --namespace=prod --rm -i -t --image=alpine -- sh
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

Traffic is allowed from prod namespace!

## Acceptance Criteria

- [ ] Web service deployed in default namespace
- [ ] Dev namespace created with label `purpose=testing`
- [ ] Prod namespace created with label `purpose=production`
- [ ] NetworkPolicy `web-allow-prod` created successfully
- [ ] Policy uses namespaceSelector with matchLabels
- [ ] Traffic from dev namespace is blocked (timeout)
- [ ] Traffic from prod namespace is allowed (successful response)
- [ ] Only production-labeled namespaces can access the service

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `web-allow-prod`
- Pod Selector: `app=web`
- Ingress Source: Namespaces with `purpose=production` label

**How It Works:**
- `podSelector` targets the application pods
- `namespaceSelector.matchLabels` selects source namespaces
- Only pods in matching namespaces can send traffic
- Namespace labels are used for access control
- Multiple namespaces can match if they have the same label

**Label-Based Selection:**
```yaml
# Select namespaces by single label
namespaceSelector:
  matchLabels:
    purpose: production

# Select namespaces by multiple labels (AND)
namespaceSelector:
  matchLabels:
    purpose: production
    team: platform

# Select using matchExpressions (more flexible)
namespaceSelector:
  matchExpressions:
  - key: environment
    operator: In
    values: [production, staging]
```

## Implementation Details

This policy uses namespace labels for access control, which is a powerful pattern for organizing Kubernetes multi-tenancy:

**Best Practices for Namespace Labels:**
- `purpose`: testing, production, development
- `team`: platform, frontend, backend, data
- `environment`: dev, staging, prod
- `criticality`: low, medium, high, critical

**Label Strategy:**
- Use consistent label taxonomy across the organization
- Document label meanings and usage
- Automate label assignment where possible
- Regularly audit namespace labels

## Verification

Check policy and namespace configuration:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy web-allow-prod

# View namespace labels
kubectl get namespaces --show-labels

# View specific namespace
kubectl describe namespace prod
kubectl describe namespace dev
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete networkpolicy web-allow-prod
kubectl delete pod web
kubectl delete service web
kubectl delete namespace prod dev
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Namespace Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors)
- [Multi-tenancy Best Practices](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

## Notes

**Best Practices:**
- Establish a namespace labeling convention
- Document label meanings in your organization
- Use labels to represent environments, teams, or criticality levels
- Combine with RBAC for comprehensive access control
- Regularly audit which namespaces can access critical services

**Common Patterns:**
```yaml
# Environment-based access
purpose: production  # Only prod namespaces

# Team-based access
team: data-science  # Only data science team

# Criticality-based access
tier: critical  # Only critical infrastructure

# Multiple criteria (all must match)
matchLabels:
  environment: production
  region: us-east
```

This pattern is essential for implementing fine-grained multi-tenancy and environment isolation in Kubernetes clusters.
