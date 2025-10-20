---
id: NP-10
title: Allow Traffic from Apps Using Multiple Selectors
type: policy
category: advanced
priority: high
status: ready
estimated_time: 20m
dependencies: [NP-00]
tags: [network-policy, multiple-selectors, or-condition, microservices, shared-services]
---

## Overview

Create a NetworkPolicy that uses multiple pod selectors to allow traffic from several different applications, enabling shared services accessible to multiple microservices.

## Objectives

- Define multiple pod selectors in a single NetworkPolicy
- Understand OR logic in ingress rules
- Enable shared databases or services for multiple microservices
- Implement fine-grained access control with multiple sources

## Background

NetworkPolicy lets you define multiple pod selectors to allow traffic from different sources. This is particularly useful for shared services that need to be accessed by multiple applications.

**Use Cases:**
- Create a combined NetworkPolicy that has the list of microservices allowed to connect to an application
- Share databases between multiple microservices in different tiers
- Allow multiple monitoring or logging tools to access application endpoints
- Enable cross-team service access with explicit whitelisting

## Requirements

### Task 1: Deploy Shared Database
**Priority:** High
**Status:** pending

Run a Redis database that will be shared by multiple microservices.

**Actions:**
- Deploy Redis pod with labels `app=bookstore` and `role=db`
- Expose service on port 6379
- Verify pod is running

**Command:**
```bash
kubectl run db --image=redis:4 --labels="app=bookstore,role=db" --expose --port=6379
```

### Task 2: Understand Microservice Architecture
**Priority:** High
**Status:** pending

Document the microservices that need access to the shared database.

**Microservice Labels:**

| Service    | Labels |
|------------|--------|
| `search`   | `app=bookstore`<br/>`role=search` |
| `api`      | `app=bookstore`<br/>`role=api` |
| `catalog`  | `app=inventory`<br/>`role=web` |

**Architecture:**
- All services need access to the Redis database
- Services have different label combinations
- Need to whitelist all three services explicitly

### Task 3: Create Multiple Selector Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that allows traffic from multiple pod selectors using OR logic.

**Actions:**
- Create `redis-allow-services.yaml` manifest
- Define multiple podSelector entries
- Apply policy to cluster

**Manifest:** `redis-allow-services.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: redis-allow-services
spec:
  podSelector:
    matchLabels:
      app: bookstore
      role: db
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: bookstore
          role: search
    - podSelector:
        matchLabels:
          app: bookstore
          role: api
    - podSelector:
        matchLabels:
          app: inventory
          role: web
```

**Key Configuration:**
- Targets pods with `app=bookstore` and `role=db` labels
- Three separate podSelector entries (OR logic)
- Each selector specifies exact label combination
- All matching pods are whitelisted

**Command:**
```bash
kubectl apply -f redis-allow-services.yaml
```

**Expected Output:**
```
networkpolicy "redis-allow-services" created
```

**Important Notes:**
- Rules specified in `spec.ingress.from` are OR'ed
- This means the pods selected by the selectors are combined
- All selected pods are whitelisted altogether
- Any pod matching at least one selector can access the database

### Task 4: Test Access as Catalog Service (Allowed)
**Priority:** High
**Status:** pending

Verify that pods matching the catalog microservice labels can access the database.

**Actions:**
- Run test pod with labels `app=inventory,role=web`
- Connect to Redis database
- Verify connection succeeds

**Commands:**
```bash
kubectl run test-$RANDOM --labels="app=inventory,role=web" --rm -i -t --image=alpine -- sh
# Inside the pod:
nc -v -w 2 db 6379
```

**Expected Result:**
```
db (10.59.242.200:6379) open
```

Connection works! Pod matches one of the allowed selectors.

### Task 5: Test Access as Search Service (Allowed)
**Priority:** High
**Status:** pending

Verify that pods matching the search microservice labels can access the database.

**Actions:**
- Run test pod with labels `app=bookstore,role=search`
- Connect to Redis database
- Verify connection succeeds

**Commands:**
```bash
kubectl run test-$RANDOM --labels="app=bookstore,role=search" --rm -i -t --image=alpine -- sh
# Inside the pod:
nc -v -w 2 db 6379
```

**Expected Result:**
```
db (10.59.242.200:6379) open
```

Connection works! Pod matches another allowed selector.

### Task 6: Test Access with Non-Whitelisted Labels (Blocked)
**Priority:** High
**Status:** pending

Verify that pods not matching any selector are blocked.

**Actions:**
- Run test pod with different labels `app=other`
- Attempt connection to database
- Confirm connection is blocked

**Commands:**
```bash
kubectl run test-$RANDOM --labels="app=other" --rm -i -t --image=alpine -- sh
# Inside the pod:
nc -v -w 2 db 6379
```

**Expected Result:**
```
nc: db (10.59.252.83:6379): Operation timed out
```

Connection blocked! Pod doesn't match any allowed selector.

## Acceptance Criteria

- [ ] Redis database deployed with labels `app=bookstore,role=db`
- [ ] Service exposed on port 6379
- [ ] NetworkPolicy `redis-allow-services` created successfully
- [ ] Policy contains three podSelector entries
- [ ] Pods with `app=bookstore,role=search` labels can connect
- [ ] Pods with `app=bookstore,role=api` labels can connect
- [ ] Pods with `app=inventory,role=web` labels can connect
- [ ] Pods with non-matching labels are blocked
- [ ] OR logic properly combines all selectors

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `redis-allow-services`
- Pod Selector: `app=bookstore` AND `role=db`
- Ingress Sources: Three pod selectors (OR'ed together)

**How It Works:**
- Multiple `from` entries create an OR condition
- A pod is allowed if it matches ANY of the selectors
- Each selector requires ALL its labels to match (AND within selector)
- Selectors are combined with OR logic (OR between selectors)

**OR Logic in Ingress Rules:**
```yaml
ingress:
- from:
  - podSelector: {...}  # Selector 1 (OR)
  - podSelector: {...}  # Selector 2 (OR)
  - podSelector: {...}  # Selector 3 (OR)
```

**Label Matching:**
- Within each podSelector: ALL labels must match (AND)
- Between podSelectors: ANY selector can match (OR)

**Example:**
```yaml
- podSelector:
    matchLabels:
      app: bookstore    # AND
      role: search      # Must have both labels
```

## Implementation Details

**Understanding OR vs AND:**

**OR between selectors (what we're using):**
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: bookstore
        role: search
  - podSelector:
      matchLabels:
        app: bookstore
        role: api
# Allows: (bookstore+search) OR (bookstore+api)
```

**AND between selectors (different syntax):**
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: bookstore
  - podSelector:
      matchLabels:
        role: search
# Allows: (bookstore) OR (search)
# Note: This is still OR, not AND!
```

**True AND requires same list item:**
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        team: operations
    podSelector:
      matchLabels:
        role: monitoring
# Allows: pods with role=monitoring in namespaces with team=operations
```

**Combining Multiple Services:**
```yaml
spec:
  podSelector:
    matchLabels:
      app: shared-cache
  ingress:
  - from:
    # Frontend services
    - podSelector:
        matchLabels:
          tier: frontend
          app: web
    - podSelector:
        matchLabels:
          tier: frontend
          app: mobile-api
    # Backend services
    - podSelector:
        matchLabels:
          tier: backend
          app: orders
    - podSelector:
        matchLabels:
          tier: backend
          app: inventory
```

**Using matchExpressions for More Flexible Matching:**
```yaml
ingress:
- from:
  - podSelector:
      matchExpressions:
      - key: app
        operator: In
        values: [bookstore, inventory]
      - key: role
        operator: In
        values: [api, search, web]
```

**Mixed Namespace and Pod Selectors:**
```yaml
ingress:
- from:
  # Allow from specific pods in same namespace
  - podSelector:
      matchLabels:
        app: service-a
  # Allow from specific pods in other namespace
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: service-b
  # Allow from all pods in monitoring namespace
  - namespaceSelector:
      matchLabels:
        purpose: monitoring
```

## Verification

Check policy and test connectivity:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy redis-allow-services

# Check which pods are selected
kubectl get pods -l app=bookstore,role=db --show-labels

# Test each service label combination
# Test search service
kubectl run test-search --labels="app=bookstore,role=search" --rm -i -t --image=alpine -- sh
# Inside: nc -v -w 2 db 6379

# Test api service
kubectl run test-api --labels="app=bookstore,role=api" --rm -i -t --image=alpine -- sh
# Inside: nc -v -w 2 db 6379

# Test catalog service
kubectl run test-catalog --labels="app=inventory,role=web" --rm -i -t --image=alpine -- sh
# Inside: nc -v -w 2 db 6379

# Test unauthorized access
kubectl run test-blocked --labels="app=unauthorized" --rm -i -t --image=alpine -- sh
# Inside: nc -v -w 2 db 6379
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod db
kubectl delete service db
kubectl delete networkpolicy redis-allow-services
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Label Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [matchExpressions](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#set-based-requirement)

## Notes

**Best Practices:**
- Document which services need access and why
- Use consistent labeling schemes across microservices
- Group related selectors together with comments
- Consider using matchExpressions for large numbers of services
- Regularly audit and update allowed services list

**Common Patterns:**

**Shared Database Pattern:**
```yaml
# Allow multiple application tiers to access database
ingress:
- from:
  - podSelector:
      matchLabels:
        tier: frontend
  - podSelector:
      matchLabels:
        tier: backend
  - podSelector:
      matchLabels:
        tier: worker
```

**Multi-Team Access Pattern:**
```yaml
# Allow specific teams to access shared service
ingress:
- from:
  - podSelector:
      matchLabels:
        team: team-a
        role: api
  - podSelector:
      matchLabels:
        team: team-b
        role: api
  - podSelector:
      matchLabels:
        team: platform
        role: admin
```

**Environment-Based Pattern:**
```yaml
# Allow services from same environment only
ingress:
- from:
  - podSelector:
      matchExpressions:
      - key: environment
        operator: In
        values: [production]
      - key: access-level
        operator: In
        values: [privileged, standard]
```

**Using matchExpressions for Scalability:**
```yaml
# More maintainable for many services
ingress:
- from:
  - podSelector:
      matchExpressions:
      # Any service with these apps
      - key: app
        operator: In
        values: [service-a, service-b, service-c, service-d]
      # AND one of these roles
      - key: role
        operator: In
        values: [api, worker]
```

**Anti-Pattern - Too Broad:**
```yaml
# Avoid: This allows any pod with ANY of these labels
ingress:
- from:
  - podSelector:
      matchLabels:
        tier: frontend
  - podSelector:
      matchLabels:
        access: enabled
# Problem: Any pod with just 'access=enabled' can connect
```

**Debugging Tips:**
```bash
# Check if pod labels match selector
kubectl get pods --show-labels | grep "app=bookstore"

# Test label matching
kubectl get pods -l "app=bookstore,role=search"

# View effective labels on pod
kubectl describe pod <pod-name> | grep Labels

# Check NetworkPolicy details
kubectl get networkpolicy redis-allow-services -o yaml

# Test connectivity from specific pod
kubectl exec -it <pod-name> -- nc -zv db 6379
```

**Common Mistakes:**
- Confusing OR between selectors with AND within a selector
- Forgetting that all labels in matchLabels must match
- Not testing all combinations of allowed services
- Using too-broad selectors that allow unintended access
- Mixing up podSelector and namespaceSelector logic

**Scaling Considerations:**
- For 5+ services, consider using matchExpressions
- Document service access matrix
- Use automation to generate policies from service registry
- Consider using service mesh for very complex scenarios
- Monitor policy effectiveness with network flow logs

**Security Considerations:**
- Principle of least privilege: only allow necessary services
- Regularly review and audit allowed services
- Remove access for deprecated services
- Consider time-based access for temporary integrations
- Log and monitor database access patterns
- Combine with authentication at application level

This pattern is essential for implementing shared services in microservice architectures while maintaining security and explicit access control.
