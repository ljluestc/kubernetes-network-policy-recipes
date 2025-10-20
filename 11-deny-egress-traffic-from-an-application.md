---
id: NP-11
title: Deny Egress Traffic from an Application
type: policy
category: egress
priority: high
status: ready
estimated_time: 25m
dependencies: [NP-00]
tags: [network-policy, egress, deny-all, outbound-traffic, dns]
---

## Overview

Implement a NetworkPolicy that prevents an application from establishing any outbound connections, useful for restricting egress traffic from single-instance databases and datastores.

## Objectives

- Block all egress (outbound) traffic from selected pods
- Understand DNS resolution requirements for network policies
- Implement selective DNS whitelisting
- Restrict outbound connections for security-sensitive applications

## Background

This NetworkPolicy denies all egress traffic from an application, preventing it from establishing any connections outside of the pod. This is useful for security-critical applications that should not initiate outbound connections.

**Use Cases:**
- Prevent applications from establishing connections outside of the pod
- Restrict outbound traffic of single-instance databases and datastores
- Implement data exfiltration protection
- Secure sensitive applications that should only respond to requests
- Prevent compromised applications from calling external services

**Important Notes:**
- If you are using Google Kubernetes Engine (GKE), make sure you have at least `1.8.4-gke.0` master and nodes version to be able to use egress policies
- Blocking all egress will also block DNS resolution unless explicitly allowed

## Requirements

### Task 1: Deploy Test Web Application
**Priority:** High
**Status:** pending

Run a web application for testing egress policies.

**Actions:**
- Deploy nginx pod with label `app=web`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --image=nginx --labels="app=web" --expose --port=80
```

### Task 2: Create Deny-All Egress Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that blocks all egress traffic.

**Actions:**
- Create `foo-deny-egress.yaml` manifest
- Configure policy to deny all outbound traffic
- Apply policy to cluster

**Manifest:** `foo-deny-egress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: foo-deny-egress
spec:
  podSelector:
    matchLabels:
      app: foo
  policyTypes:
  - Egress
  egress: []
```

**Key Configuration:**
- `podSelector` matches to `app=foo` pods
- `policyTypes: ["Egress"]` indicates this policy enforces egress (outbound) traffic
- `egress: []` empty rule set does not whitelist any traffic, therefore all egress traffic is blocked
- You can drop the egress field altogether and have the same effect

**Command:**
```bash
kubectl apply -f foo-deny-egress.yaml
```

**Expected Output:**
```
networkpolicy "foo-deny-egress" created
```

### Task 3: Test Egress Blocking Without DNS
**Priority:** High
**Status:** pending

Verify that egress traffic is blocked, including DNS resolution.

**Actions:**
- Run test pod with label `app=foo`
- Attempt connection to internal service
- Attempt connection to external service
- Observe DNS resolution failure

**Commands:**
```bash
kubectl run --rm --restart=Never --image=alpine -i -t --labels="app=foo" test -- ash
# Inside the pod:
wget -qO- --timeout 1 http://web:80/
wget -qO- --timeout 1 http://www.example.com/
```

**Expected Result:**
```
wget: bad address 'web:80'
wget: bad address 'www.example.com'
```

**What's Happening:**
- The pod is failing to resolve addresses
- Network policy is not allowing connections to kube-dns pods
- DNS resolution is blocked along with all other egress traffic

### Task 4: Update Policy to Allow DNS
**Priority:** High
**Status:** pending

Modify the policy to allow DNS resolution while blocking other traffic.

**Actions:**
- Update policy to allow DNS traffic to kube-dns
- Allow both UDP and TCP on port 53
- Use namespace and pod selectors to target kube-dns

**Updated Manifest:** `foo-deny-egress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: foo-deny-egress
spec:
  podSelector:
    matchLabels:
      app: foo
  policyTypes:
  - Egress
  egress:
  # allow DNS resolution
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

**Key Changes:**
- Added egress rule for DNS
- Targets kube-system namespace
- Selects kube-dns pods specifically
- Allows both UDP and TCP on port 53
- All other traffic remains blocked

**Command:**
```bash
kubectl apply -f foo-deny-egress.yaml
```

### Task 5: Test Egress Blocking With DNS
**Priority:** High
**Status:** pending

Verify DNS resolution works but connections are still blocked.

**Actions:**
- Run test pod with label `app=foo`
- Verify DNS resolution succeeds
- Verify connections to resolved IPs are blocked
- Test both internal and external services

**Commands:**
```bash
kubectl run --rm --restart=Never --image=alpine -i -t --labels="app=foo" test -- ash
# Inside the pod:
wget --timeout 1 -O- http://web
```

**Expected Result:**
```
Connecting to web (10.59.245.232:80)
wget: download timed out
```

DNS resolution works (IP address shown), but connection is blocked!

**Test external service:**
```bash
# Inside the same pod:
wget --timeout 1 -O- http://www.example.com
```

**Expected Result:**
```
Connecting to www.example.com (93.184.216.34:80)
wget: download timed out
```

DNS resolution works, but connection is blocked!

**Test ping:**
```bash
# Inside the same pod:
ping google.com
```

**Expected Result:**
```
PING google.com (74.125.129.101): 56 data bytes
(no response, hit Ctrl+C to terminate)
```

DNS works, but ICMP traffic is blocked!

## Acceptance Criteria

- [ ] Web service deployed in cluster
- [ ] NetworkPolicy `foo-deny-egress` created successfully
- [ ] Policy targets pods with `app=foo` label
- [ ] Policy specifies Egress policyType
- [ ] Initial policy blocks all egress including DNS
- [ ] Updated policy allows DNS to kube-dns
- [ ] DNS resolution works for internal and external names
- [ ] Actual connections to resolved IPs are blocked
- [ ] Both TCP and ICMP traffic blocked

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `foo-deny-egress`
- Pod Selector: `app=foo`
- Policy Types: Egress
- Egress Rules: DNS only (to kube-dns in kube-system)

**How It Works:**
- `policyTypes: [Egress]` enforces egress policy
- Empty `egress: []` blocks all outbound traffic
- Adding DNS rule allows name resolution
- `namespaceSelector` + `podSelector` creates AND condition
- Only kube-dns pods in kube-system namespace are reachable
- All other egress traffic is denied

**Egress Policy Behavior:**
```yaml
# Deny all egress
egress: []

# Allow specific egress (DNS)
egress:
- to:
  - namespaceSelector: {...}
    podSelector: {...}
  ports:
  - port: 53
    protocol: UDP
  - port: 53
    protocol: TCP
```

**DNS Resolution Flow:**
```
Pod (app=foo)
    ↓ (DNS query - allowed)
kube-dns (kube-system)
    ↓ (DNS response - allowed)
Pod (app=foo)
    ↓ (HTTP connection - blocked)
✗ Blocked by NetworkPolicy
```

## Implementation Details

**Understanding Egress Policies:**

**Complete Deny (no DNS):**
```yaml
policyTypes:
- Egress
egress: []  # Blocks everything including DNS
```

**Deny with DNS Exception:**
```yaml
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

**Why Both UDP and TCP for DNS:**
- DNS typically uses UDP for queries
- TCP is used for large responses (over 512 bytes)
- Zone transfers use TCP
- Both should be allowed for reliable DNS

**Alternative DNS Selectors:**
```yaml
# Using CoreDNS (common in newer clusters)
podSelector:
  matchLabels:
    k8s-app: kube-dns  # Works for both kube-dns and CoreDNS

# More specific CoreDNS selector
podSelector:
  matchLabels:
    k8s-app: kube-dns
    app.kubernetes.io/name: coredns
```

**Common Egress Patterns:**

**Allow Egress to Specific Services:**
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
# Specific internal service
- to:
  - podSelector:
      matchLabels:
        app: backend-api
  ports:
  - port: 8080
```

**Allow Egress to External IPs:**
```yaml
egress:
- to:
  - ipBlock:
      cidr: 10.0.0.0/8  # Internal network
- to:
  - ipBlock:
      cidr: 203.0.113.0/24  # Specific external range
  ports:
  - port: 443
```

## Verification

Check policy and test connectivity:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy foo-deny-egress

# Check kube-dns pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run test-dns --labels="app=foo" --rm -i -t --image=alpine -- sh
# Inside:
nslookup kubernetes.default
nslookup google.com

# Test actual connectivity
kubectl run test-conn --labels="app=foo" --rm -i -t --image=alpine -- sh
# Inside:
wget -O- --timeout=2 http://web
wget -O- --timeout=2 http://www.example.com
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod,service web
kubectl delete networkpolicy foo-deny-egress
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Egress Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-egress-traffic)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## Notes

**Best Practices:**
- Always allow DNS unless you have a specific reason not to
- Use specific namespace and pod selectors for DNS
- Test both DNS resolution and actual connectivity
- Document why egress is blocked for specific applications
- Monitor for legitimate egress requirements

**Common Use Cases:**

**Database with No Egress:**
```yaml
# PostgreSQL that only accepts connections
spec:
  podSelector:
    matchLabels:
      app: postgresql
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

**API Gateway with Limited Egress:**
```yaml
# Only allow egress to specific backend services
spec:
  podSelector:
    matchLabels:
      app: api-gateway
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
  # Backend services
  - to:
    - podSelector:
        matchLabels:
          tier: backend
```

**Debugging Tips:**
```bash
# Check if DNS is working
kubectl exec -it <pod> -- nslookup kubernetes.default

# Check if egress policy is applied
kubectl get networkpolicy -o yaml

# View kube-dns endpoint
kubectl get endpoints -n kube-system kube-dns

# Test DNS with dig
kubectl exec -it <pod> -- dig @<kube-dns-ip> google.com

# Check pod connectivity to DNS
kubectl exec -it <pod> -- nc -zv <kube-dns-ip> 53
```

**Common Mistakes:**
- Forgetting to allow DNS (leads to name resolution failures)
- Only allowing UDP for DNS (TCP needed for large responses)
- Not using both namespace and pod selectors for DNS
- Assuming the policy blocks ingress (it only blocks egress)
- Blocking legitimate health checks or monitoring

**Security Considerations:**
- Egress policies are defense-in-depth
- Don't rely solely on network policies for security
- Combine with:
  - Container security policies
  - Application-level security
  - Network segmentation
  - Monitoring and alerting
- Regularly review egress requirements
- Monitor for policy violations

**GKE Specific Notes:**
- Requires GKE version 1.8.4-gke.0 or later
- Egress policies may have performance impact
- Test thoroughly before production deployment
- Check GKE release notes for CNI plugin updates

**DNS Configuration Notes:**
- Different clusters may use different DNS labels
- CoreDNS is common in newer clusters
- Check your cluster's DNS pod labels:
  ```bash
  kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels
  ```
- Adjust the policy to match your DNS pod labels

**Performance Considerations:**
- Egress policies can impact network performance
- Test application performance after applying policies
- Monitor for increased latency
- Consider the overhead of policy evaluation

This pattern is essential for implementing zero-trust networking and preventing data exfiltration from sensitive applications.
