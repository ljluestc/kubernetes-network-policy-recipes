---
id: NP-13
title: Allow Egress Traffic to Specific Pods
type: policy
category: egress
priority: high
status: ready
estimated_time: 25m
dependencies: [NP-00, NP-11, NP-12]
tags: [network-policy, egress, pod-selector, selective-egress, microservices]
---

## Overview

Implement a NetworkPolicy that allows an application to establish outbound connections only to specific pods, enabling fine-grained egress control for microservices architectures.

## Objectives

- Allow egress traffic only to specific pods using label selectors
- Implement selective egress control for microservices
- Whitelist DNS resolution alongside specific pod access
- Understand egress policy patterns for service dependencies

## Background

This NetworkPolicy allows an application to establish outbound connections only to specific pods in the cluster. This is useful for implementing the principle of least privilege in microservices architectures, where services should only communicate with their direct dependencies.

**Use Cases:**
- Restrict frontend applications to communicate only with specific backend APIs
- Allow worker pods to connect only to designated message queues
- Limit application egress to specific database pods
- Implement strict service dependency graphs
- Prevent lateral movement in compromised applications

**Important Notes:**
- Egress policies require Kubernetes v1.8+ (GKE 1.8.4-gke.0+)
- Always whitelist DNS unless you use IP addresses directly
- Combine with ingress policies for comprehensive network security

![Diagram of ALLOW egress traffic to specific pods policy](img/13.gif)

## Requirements

### Task 1: Deploy Backend API Service
**Priority:** High
**Status:** pending

Deploy a backend API service that will be the target of allowed egress traffic.

**Actions:**
- Deploy nginx as backend API with label `app=backend-api`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run backend-api --image=nginx --labels="app=backend-api,role=api" --expose --port=80
```

### Task 2: Deploy Frontend Application
**Priority:** High
**Status:** pending

Deploy a frontend application that will have restricted egress.

**Actions:**
- Deploy nginx as frontend with label `app=frontend`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run frontend --image=nginx --labels="app=frontend,role=web" --expose --port=80
```

### Task 3: Test Initial Connectivity (Before Policy)
**Priority:** High
**Status:** pending

Verify egress connectivity works before applying restrictions.

**Actions:**
- Exec into frontend pod
- Test connectivity to backend-api
- Test connectivity to external services
- Confirm DNS resolution works

**Commands:**
```bash
# Get frontend pod name
kubectl get pods -l app=frontend

# Test connectivity to backend
kubectl exec -it frontend -- wget -qO- --timeout=2 http://backend-api
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
```

Connectivity works without restrictions.

**Test external connectivity:**
```bash
kubectl exec -it frontend -- wget -qO- --timeout=2 http://www.example.com
```

Should succeed (internet access works).

### Task 4: Create Selective Egress Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that allows egress only to DNS and specific backend pods.

**Actions:**
- Create `frontend-allow-egress-to-backend.yaml` manifest
- Configure egress to kube-dns for DNS resolution
- Configure egress to backend-api pods only
- Apply policy to cluster

**Manifest:** `frontend-allow-egress-to-backend.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-allow-egress-to-backend
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  # Allow DNS resolution
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
  # Allow egress to backend-api pods
  - to:
    - podSelector:
        matchLabels:
          app: backend-api
    ports:
    - port: 80
      protocol: TCP
```

**Key Configuration:**
- `podSelector` targets pods with `app=frontend` label
- `policyTypes: [Egress]` enforces egress policy
- First egress rule: Allow DNS (UDP/TCP port 53 to kube-dns)
- Second egress rule: Allow HTTP (TCP port 80 to backend-api pods)
- All other egress traffic is denied

**Command:**
```bash
kubectl apply -f frontend-allow-egress-to-backend.yaml
```

**Expected Output:**
```
networkpolicy.networking.k8s.io/frontend-allow-egress-to-backend created
```

### Task 5: Verify DNS Resolution Works
**Priority:** High
**Status:** pending

Confirm DNS resolution is functional after policy application.

**Actions:**
- Test DNS resolution for internal services
- Test DNS resolution for external domains
- Verify DNS queries succeed

**Commands:**
```bash
kubectl exec -it frontend -- nslookup backend-api
```

**Expected Result:**
```
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	backend-api.default.svc.cluster.local
Address: 10.100.200.50
```

DNS resolution works!

**Test external DNS:**
```bash
kubectl exec -it frontend -- nslookup google.com
```

**Expected Result:**
```
Server:		10.96.0.10
Address:	10.96.0.10:53

Non-authoritative answer:
Name:	google.com
Address: 142.250.185.46
```

DNS resolution works for external domains too!

### Task 6: Verify Allowed Egress to Backend
**Priority:** High
**Status:** pending

Confirm egress traffic to backend-api is allowed.

**Actions:**
- Connect from frontend to backend-api
- Verify successful HTTP response
- Confirm DNS resolution and connection both work

**Command:**
```bash
kubectl exec -it frontend -- wget -qO- --timeout=2 http://backend-api
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

Connection to backend-api is allowed!

### Task 7: Verify Blocked Egress to External Services
**Priority:** High
**Status:** pending

Confirm egress traffic to external services is blocked.

**Actions:**
- Attempt connection to external service
- Verify DNS resolves but connection times out
- Confirm egress blocking is working

**Command:**
```bash
kubectl exec -it frontend -- wget -qO- --timeout=2 http://www.example.com
```

**Expected Result:**
```
Connecting to www.example.com (93.184.216.34:80)
wget: download timed out
```

DNS resolution works, but connection is blocked!

### Task 8: Verify Blocked Egress to Other Pods
**Priority:** High
**Status:** pending

Deploy another pod and confirm egress to it is blocked.

**Actions:**
- Deploy another service (e.g., database)
- Attempt connection from frontend
- Verify connection is blocked

**Commands:**
```bash
# Deploy database pod
kubectl run database --image=nginx --labels="app=database" --expose --port=80

# Try to connect from frontend
kubectl exec -it frontend -- wget -qO- --timeout=2 http://database
```

**Expected Result:**
```
Connecting to database (10.100.200.75:80)
wget: download timed out
```

Egress to non-whitelisted pods is blocked!

## Acceptance Criteria

- [ ] Backend API service deployed with label `app=backend-api`
- [ ] Frontend application deployed with label `app=frontend`
- [ ] NetworkPolicy `frontend-allow-egress-to-backend` created successfully
- [ ] Policy specifies Egress policyType
- [ ] DNS resolution works for internal and external names
- [ ] Egress to backend-api pods is allowed
- [ ] Egress to external services is blocked (DNS resolves, connection times out)
- [ ] Egress to other internal pods is blocked
- [ ] Only DNS and backend-api traffic is permitted

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `frontend-allow-egress-to-backend`
- Pod Selector: `app=frontend`
- Policy Types: Egress
- Egress Rules:
  1. DNS to kube-dns (UDP/TCP port 53)
  2. HTTP to backend-api pods (TCP port 80)

**How It Works:**
- `policyTypes: [Egress]` activates egress enforcement
- Multiple egress rules are evaluated with OR logic
- Traffic matching ANY rule is allowed
- Traffic matching NO rule is blocked
- DNS must be explicitly whitelisted
- Pod selectors identify allowed destination pods

**Egress Rule Behavior:**
```yaml
# Rule 1: Allow DNS
egress:
- to:
  - namespaceSelector: {...}  # kube-system
    podSelector: {...}         # kube-dns
  ports:
  - port: 53

# Rule 2: Allow backend access
- to:
  - podSelector: {...}  # backend-api
  ports:
  - port: 80
```

**Traffic Flow:**
```
Frontend Pod
    ↓ DNS query (port 53)
kube-dns (allowed by rule 1)
    ↓ DNS response
Frontend Pod
    ↓ HTTP request (port 80)
Backend-api Pod (allowed by rule 2)
    ↓ HTTP response
Frontend Pod
    ↓ HTTP request (port 80)
✗ External Service (blocked - no matching rule)
```

## Implementation Details

**Understanding Selective Egress:**

**Complete Egress Allow:**
```yaml
# No egress field = all egress allowed (default)
spec:
  podSelector:
    matchLabels:
      app: frontend
# No policyTypes means only ingress is enforced
```

**Complete Egress Deny:**
```yaml
# Empty egress array blocks everything
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress: []
```

**Selective Egress (DNS + Specific Pods):**
```yaml
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  # DNS
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
  # Specific pods
  - to:
    - podSelector:
        matchLabels:
          app: backend-api
    ports:
    - port: 80
      protocol: TCP
```

**Multiple Egress Destinations:**
```yaml
egress:
# DNS
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
# Backend API
- to:
  - podSelector:
      matchLabels:
        app: backend-api
  ports:
  - port: 80
# Message Queue
- to:
  - podSelector:
      matchLabels:
        app: rabbitmq
  ports:
  - port: 5672
# Database
- to:
  - podSelector:
      matchLabels:
        app: postgresql
  ports:
  - port: 5432
```

**Cross-Namespace Egress:**
```yaml
# Allow egress to pods in specific namespace
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: backend-services
    podSelector:
      matchLabels:
        app: api
  ports:
  - port: 8080
```

**Combining Pod and Namespace Selectors:**
```yaml
# AND condition: specific pods in specific namespace
- to:
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: backend
  ports:
  - port: 8080
```

## Real-World Examples

### Example 1: Frontend to Backend API Pattern
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Egress
  egress:
  # DNS
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
  # Backend API (same namespace)
  - to:
    - podSelector:
        matchLabels:
          tier: backend
          app: api-server
    ports:
    - port: 8080
      protocol: TCP
  # Authentication service (different namespace)
  - to:
    - namespaceSelector:
        matchLabels:
          name: auth-services
      podSelector:
        matchLabels:
          app: auth-server
    ports:
    - port: 9090
      protocol: TCP
```

### Example 2: Microservice with Database Access
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-service-egress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: api-service
  policyTypes:
  - Egress
  egress:
  # DNS
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
  # PostgreSQL database
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
          role: primary
    ports:
    - port: 5432
      protocol: TCP
  # Redis cache
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - port: 6379
      protocol: TCP
```

### Example 3: Worker Pod with Message Queue
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: worker-egress
  namespace: jobs
spec:
  podSelector:
    matchLabels:
      app: background-worker
  policyTypes:
  - Egress
  egress:
  # DNS
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
  # RabbitMQ
  - to:
    - namespaceSelector:
        matchLabels:
          name: messaging
      podSelector:
        matchLabels:
          app: rabbitmq
    ports:
    - port: 5672
      protocol: TCP
  # S3 API endpoint (for file storage)
  - to:
    - podSelector:
        matchLabels:
          app: minio
    ports:
    - port: 9000
      protocol: TCP
```

### Example 4: Multi-tier Application
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: webapp-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: webapp
      tier: middle
  policyTypes:
  - Egress
  egress:
  # DNS
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
  # Backend services (same namespace)
  - to:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - port: 8080
      protocol: TCP
  # Monitoring (metrics export)
  - to:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - port: 9090
      protocol: TCP
```

## Debugging Tips

**Check Policy Configuration:**
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy frontend-allow-egress-to-backend

# View policy in YAML
kubectl get networkpolicy frontend-allow-egress-to-backend -o yaml
```

**Verify Pod Labels:**
```bash
# Check frontend pod labels
kubectl get pods -l app=frontend --show-labels

# Check backend pod labels
kubectl get pods -l app=backend-api --show-labels

# Check all pod labels in namespace
kubectl get pods --show-labels
```

**Test DNS Resolution:**
```bash
# Test internal DNS
kubectl exec -it frontend -- nslookup backend-api

# Test external DNS
kubectl exec -it frontend -- nslookup google.com

# Check DNS server
kubectl exec -it frontend -- cat /etc/resolv.conf
```

**Test Connectivity:**
```bash
# Test with wget
kubectl exec -it frontend -- wget -qO- --timeout=2 http://backend-api

# Test with curl
kubectl exec -it frontend -- curl -m 2 http://backend-api

# Test with netcat
kubectl exec -it frontend -- nc -zv backend-api 80

# Test with telnet
kubectl exec -it frontend -- telnet backend-api 80
```

**Check kube-dns:**
```bash
# Find kube-dns pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check kube-dns labels
kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels

# Test DNS directly
kubectl exec -it frontend -- dig @<kube-dns-ip> backend-api
```

**Verify Service Endpoints:**
```bash
# Check backend service
kubectl get service backend-api

# Check service endpoints
kubectl get endpoints backend-api

# Describe service
kubectl describe service backend-api
```

## Verification

Comprehensive verification checklist:

```bash
# 1. Verify policy exists and targets correct pods
kubectl get networkpolicy
kubectl describe networkpolicy frontend-allow-egress-to-backend

# 2. Check pod labels match policy selectors
kubectl get pods -l app=frontend --show-labels
kubectl get pods -l app=backend-api --show-labels

# 3. Test DNS resolution (should work)
kubectl exec -it frontend -- nslookup backend-api
kubectl exec -it frontend -- nslookup google.com

# 4. Test allowed egress (should succeed)
kubectl exec -it frontend -- wget -qO- --timeout=2 http://backend-api

# 5. Test blocked egress to external (should timeout)
kubectl exec -it frontend -- wget -qO- --timeout=2 http://www.example.com

# 6. Test blocked egress to other pods (should timeout)
kubectl run other-service --image=nginx --expose --port=80
kubectl exec -it frontend -- wget -qO- --timeout=2 http://other-service

# 7. Verify from non-policy pod (should work unrestricted)
kubectl run test-pod --rm -i -t --image=alpine -- sh
# Inside: wget -qO- http://www.example.com
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod frontend backend-api database
kubectl delete service frontend backend-api database
kubectl delete networkpolicy frontend-allow-egress-to-backend
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Egress Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-egress-traffic)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Label Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)

## Notes

**Best Practices:**
- Always explicitly allow DNS for service name resolution
- Document service dependencies for each microservice
- Use consistent labeling schemes across applications
- Test both positive and negative cases
- Start with deny-all, then whitelist necessary traffic
- Combine with ingress policies for comprehensive security
- Regular audit of egress policies

**Common Use Cases:**

**Three-Tier Application:**
```
Frontend → Backend API → Database
  (NP)   →    (NP)    →   (NP)

Frontend egress: DNS + Backend API
Backend egress: DNS + Database
Database egress: DNS only (or deny all)
```

**Microservices Architecture:**
```
Gateway → [Service A, Service B, Service C] → Database
  (NP)   →         (NP)                      →   (NP)

Gateway egress: DNS + ServiceA + ServiceB + ServiceC
ServiceA egress: DNS + ServiceB + Database
ServiceB egress: DNS + ServiceC + Database
ServiceC egress: DNS + Database
```

**Batch Processing:**
```
Scheduler → Worker Pods → Message Queue → Database
   (NP)   →     (NP)    →      (NP)      →   (NP)

Scheduler egress: DNS + Workers + MessageQueue
Workers egress: DNS + MessageQueue + Database
MessageQueue egress: DNS only
Database egress: DNS only (or deny all)
```

**Common Mistakes:**
- Forgetting to allow DNS (leads to service resolution failures)
- Using service ports instead of pod ports
- Not testing DNS resolution separately from connectivity
- Assuming egress policies block ingress (they don't)
- Forgetting namespace selectors for cross-namespace communication
- Not documenting service dependencies
- Over-permissive selectors (e.g., allowing all pods with certain label)

**Troubleshooting Common Issues:**

**Issue: DNS not working**
```bash
# Check if DNS is in the egress rules
kubectl get networkpolicy <name> -o yaml | grep -A 10 egress

# Verify kube-dns pods exist
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS directly
kubectl exec -it <pod> -- nslookup kubernetes.default
```

**Issue: Connection to allowed pod fails**
```bash
# Verify backend pod exists and has correct labels
kubectl get pods -l app=backend-api --show-labels

# Check if backend service exists
kubectl get service backend-api

# Verify pod is listening on specified port
kubectl exec -it backend-api -- netstat -tlnp

# Check if NetworkPolicy has correct podSelector
kubectl get networkpolicy <name> -o yaml | grep -A 5 podSelector
```

**Issue: Egress still allowed to blocked destinations**
```bash
# Check if policy exists and targets correct pods
kubectl describe networkpolicy <name>

# Verify pod has matching labels
kubectl get pod <name> --show-labels

# Check if there are other NetworkPolicies that might be allowing traffic
kubectl get networkpolicy -o yaml

# Check CNI plugin logs for policy enforcement
kubectl logs -n kube-system -l k8s-app=calico-node
```

**Security Considerations:**
- Egress policies implement defense-in-depth
- Should be combined with:
  - Ingress NetworkPolicies
  - Pod Security Standards/Admission
  - Service mesh mTLS
  - Application-level authentication
  - Network segmentation
  - Monitoring and alerting
- Egress policies prevent:
  - Unauthorized external communication
  - Lateral movement within cluster
  - Data exfiltration
  - Compromised pods calling out to C&C servers
- Egress policies DON'T prevent:
  - Attacks within allowed traffic flows
  - Application-level vulnerabilities
  - Privilege escalation
  - Host-level attacks

**Performance Considerations:**
- Egress policies add minimal overhead
- Evaluated at CNI plugin level
- Large numbers of rules can impact performance
- Test performance with realistic workloads
- Monitor for increased latency
- Consider rule complexity vs. security benefit

**GKE Specific Notes:**
- Requires GKE version 1.8.4-gke.0 or later
- Network Policy must be enabled on cluster
- Uses Calico for policy enforcement
- Check GKE release notes for feature updates
- Test policies after GKE upgrades

**Alternative Approaches:**

**Using Named Ports:**
```yaml
# In pod specification
ports:
- name: http
  containerPort: 8080
- name: metrics
  containerPort: 9090

# In NetworkPolicy
egress:
- to:
  - podSelector:
      matchLabels:
        app: backend
  ports:
  - port: http  # References named port
```

**Using IP Blocks (for external services):**
```yaml
egress:
# Allow specific external IP range
- to:
  - ipBlock:
      cidr: 203.0.113.0/24
  ports:
  - port: 443
    protocol: TCP
```

**Combining Multiple Conditions:**
```yaml
egress:
# Allow to specific pods in specific namespace on specific ports
- to:
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: api-server
  ports:
  - port: 8080
    protocol: TCP
  - port: 8443
    protocol: TCP
```

This pattern is essential for implementing least-privilege networking in microservices architectures, where services should only communicate with their direct dependencies.
