---
id: NP-14
title: Deny External Egress Traffic
type: policy
category: egress
priority: high
status: ready
estimated_time: 20m
dependencies: [NP-00]
tags: [network-policy, egress, external-traffic, cluster-internal, dns]
---

## Overview

Implement a NetworkPolicy that limits egress traffic to pods within the cluster only, preventing applications from establishing connections to external networks while allowing internal cluster communication.

## Objectives

- Block external egress traffic while allowing internal cluster communication
- Allow DNS resolution for service discovery
- Restrict applications from accessing external networks
- Implement internal-only network segmentation

## Background

This NetworkPolicy prevents applications from establishing connections to external networks while allowing communication with other pods in the cluster. This is also known as limiting traffic to pods in the cluster.

**Use Cases:**
- Prevent certain types of applications from establishing connections to external networks
- Restrict data exfiltration to external services
- Enforce internal-only communication for sensitive services
- Implement network segmentation between internal and external traffic
- Secure backend services that should only communicate internally

**Important Notes:**
- If you are using Google Kubernetes Engine (GKE), make sure you have at least `1.8.4-gke.0` master and nodes version to be able to use egress policies
- This policy allows internal cluster traffic but blocks external destinations

## Requirements

### Task 1: Create Policy Blocking External Egress
**Priority:** High
**Status:** pending

Create NetworkPolicy that allows internal cluster traffic and DNS but blocks external egress.

**Actions:**
- Create `foo-deny-external-egress.yaml` manifest
- Configure DNS access to kube-dns
- Block all external IP addresses
- Apply policy to cluster

**Manifest:** `foo-deny-external-egress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: foo-deny-external-egress
spec:
  podSelector:
    matchLabels:
      app: foo
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

**Key Configuration:**
- `podSelector` targets pods with `app=foo` label
- `policyTypes: [Egress]` enforces egress policy
- Single egress rule allows DNS to kube-dns
- No other egress rules means only DNS is allowed
- Implicit deny for all other egress traffic

**Important Notes:**
- This policy applies to pods with `app=foo` and affects Egress (outbound) direction
- Similar to NP-11 (deny egress from application), this policy allows all outbound traffic on ports 53/udp and 53/tcp to kube-dns pods for DNS resolution
- The `to` section specifies a `namespaceSelector` which matches `kubernetes.io/metadata.name: kube-system` and a `podSelector` which matches `k8s-app: kube-dns`
- This will select only the kube-dns pods in the kube-system namespace, so outbound traffic to kube-dns pods will be allowed
- Since IP addresses outside the cluster are not listed, traffic to external IPs is denied

**Command:**
```bash
kubectl apply -f foo-deny-external-egress.yaml
```

**Expected Output:**
```
networkpolicy "foo-deny-egress" created
```

### Task 2: Deploy Internal Web Service
**Priority:** High
**Status:** pending

Run a web application to test internal connectivity.

**Actions:**
- Deploy nginx pod with label `app=web`
- Expose service on port 80
- Verify pod is running

**Command:**
```bash
kubectl run web --image=nginx --labels="app=web" --expose --port=80
```

### Task 3: Test Internal Cluster Communication (Allowed)
**Priority:** High
**Status:** pending

Verify that pods can communicate with internal services.

**Actions:**
- Run test pod with label `app=foo`
- Connect to internal web service
- Verify connection succeeds

**Commands:**
```bash
kubectl run --rm --restart=Never --image=alpine -i -t --labels="app=foo" test -- ash
# Inside the pod:
wget -O- --timeout 1 http://web:80
```

**Expected Result:**
```
Connecting to web (10.59.245.232:80)
<!DOCTYPE html>
<html>
...
```

Connection is allowed! Pod can reach internal services.

### Task 4: Test External Network Communication (Blocked)
**Priority:** High
**Status:** pending

Verify that external connections are blocked.

**Actions:**
- Run test pod with label `app=foo` (or use existing pod)
- Attempt connection to external service
- Verify connection is blocked

**Commands:**
```bash
# Inside the same pod:
wget -O- --timeout 1 http://www.example.com
```

**Expected Result:**
```
Connecting to www.example.com (93.184.216.34:80)
wget: download timed out
```

Connection is blocked! The pod can resolve the IP address of `www.example.com`, however it cannot establish a connection. Effectively, external traffic is blocked.

### Task 5: Verify DNS Resolution Works
**Priority:** High
**Status:** pending

Confirm DNS resolution is functioning for both internal and external names.

**Actions:**
- Test DNS resolution for internal service
- Test DNS resolution for external service
- Verify both resolve successfully

**Commands:**
```bash
# Inside the test pod:
nslookup web
nslookup www.example.com
```

**Expected Result:**
Both names resolve to IP addresses successfully. DNS is working, but actual connections to external IPs are blocked.

## Acceptance Criteria

- [ ] NetworkPolicy `foo-deny-external-egress` created successfully
- [ ] Policy targets pods with `app=foo` label
- [ ] Policy specifies Egress policyType
- [ ] DNS access to kube-dns is allowed
- [ ] Both UDP and TCP port 53 are allowed for DNS
- [ ] Internal cluster communication is allowed
- [ ] DNS resolution works for internal and external names
- [ ] Connections to external IP addresses are blocked
- [ ] Web service accessible internally

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `foo-deny-external-egress`
- Pod Selector: `app=foo`
- Policy Types: Egress
- Egress Rules: DNS only (to kube-dns)

**How It Works:**
- Policy targets pods with `app=foo` label
- Only explicit egress rule is for DNS
- DNS resolution allowed to kube-dns in kube-system
- No rules for external IPs means they're blocked
- Internal pod-to-pod communication is allowed by Kubernetes default
- External traffic is implicitly denied

**Traffic Flow:**

**Allowed:**
```
Pod (app=foo)
    ↓ DNS query
kube-dns (kube-system) ✓
    ↓ DNS response
Pod (app=foo)
    ↓ Connection to internal service IP
Internal Service (web) ✓
```

**Blocked:**
```
Pod (app=foo)
    ↓ DNS query
kube-dns (kube-system) ✓
    ↓ DNS response with external IP
Pod (app=foo)
    ↓ Connection to external IP
External IP (93.184.216.34) ✗ BLOCKED
```

**Why Internal Traffic Works:**
By default, Kubernetes allows all pod-to-pod traffic unless restricted by NetworkPolicy. This policy only restricts egress to external destinations. Internal cluster IPs are not restricted because:
1. No ipBlock rules are specified
2. Kubernetes defaults allow internal communication
3. Only external traffic (IPs outside cluster CIDR) is blocked

## Implementation Details

**Understanding Internal vs External:**

**This Policy (Blocks External Only):**
```yaml
egress:
- to:
  - namespaceSelector: {...}
    podSelector: {...}
  ports:
  - port: 53
    protocol: UDP
  - port: 53
    protocol: TCP
# No other rules = external IPs blocked
# Internal pod IPs allowed by default
```

**Alternative: Explicit Internal Allow:**
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
# Internal cluster CIDR
- to:
  - ipBlock:
      cidr: 10.0.0.0/8  # Cluster internal CIDR
# Specific external IPs (if needed)
- to:
  - ipBlock:
      cidr: 203.0.113.0/24
  ports:
  - port: 443
```

**Using ipBlock for Precise Control:**
```yaml
egress:
- to:
  # Allow internal cluster network
  - ipBlock:
      cidr: 10.0.0.0/8
      except:
      - 10.0.1.0/24  # Block specific internal subnet
  # Allow specific external service
  - ipBlock:
      cidr: 203.0.113.10/32
  ports:
  - port: 443
```

**Pattern: Database with Limited External Access:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-internal-only
spec:
  podSelector:
    matchLabels:
      app: database
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
  # Internal cluster only (no external traffic)
```

**Pattern: Backend with Specific External API:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-limited-external
spec:
  podSelector:
    matchLabels:
      app: backend
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
  # Specific external API
  - to:
    - ipBlock:
        cidr: 52.1.2.3/32  # Specific external API server
    ports:
    - port: 443
```

## Verification

Check policy and test connectivity:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy foo-deny-external-egress

# Test internal connectivity
kubectl run test-internal --labels="app=foo" --rm -i -t --image=alpine -- sh
# Inside:
wget -O- http://web
nslookup web

# Test external connectivity (should fail)
kubectl run test-external --labels="app=foo" --rm -i -t --image=alpine -- sh
# Inside:
wget -O- --timeout=2 http://www.example.com
ping 8.8.8.8

# Check DNS resolution
kubectl run test-dns --labels="app=foo" --rm -i -t --image=alpine -- sh
# Inside:
nslookup google.com  # Should resolve
wget -O- --timeout=2 http://google.com  # Should timeout
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod,service web
kubectl delete networkpolicy foo-deny-external-egress
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Egress Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-egress-traffic)
- [IP Block](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#ipblock-v1-networking-k8s-io)

## Notes

**Best Practices:**
- Always allow DNS unless you have a specific reason not to
- Document which services need external access and why
- Use ipBlock for explicit external service allowlisting
- Test both internal and external connectivity
- Monitor for blocked legitimate external requests

**Common Use Cases:**

**Backend Service (No External Access):**
```yaml
# Backend that only talks to internal services
spec:
  podSelector:
    matchLabels:
      tier: backend
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

**Payment Service (Specific External Gateway):**
```yaml
# Payment service to specific payment gateway
spec:
  podSelector:
    matchLabels:
      app: payment-service
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
  # Payment gateway
  - to:
    - ipBlock:
        cidr: 52.123.45.67/32
    ports:
    - port: 443
```

**Meme Reference:**
The meme below can be used to explain how your cluster looks like with a policy like this:

![Network Policy Meme](https://user-images.githubusercontent.com/14810215/126358758-5b14dcd3-79df-4f85-a248-ee6b36e2e90e.png)

*Source: https://twitter.com/memenetes/status/1417227948206211082*

**Debugging Tips:**
```bash
# Check cluster CIDR range
kubectl cluster-info dump | grep -i cidr

# Test DNS resolution
kubectl exec -it <pod> -- nslookup kubernetes.default

# Test internal connectivity
kubectl exec -it <pod> -- nc -zv <service-name> <port>

# Test external connectivity (should fail)
kubectl exec -it <pod> -- nc -zv 8.8.8.8 53

# View effective NetworkPolicies
kubectl get networkpolicy -A
kubectl describe networkpolicy <name>

# Check kube-dns endpoints
kubectl get endpoints -n kube-system kube-dns
```

**Common Mistakes:**
- Not allowing DNS (leads to service discovery failures)
- Blocking legitimate external dependencies (APIs, databases)
- Not understanding cluster CIDR ranges
- Assuming internal traffic is automatically blocked
- Forgetting about IPv6 addresses

**Security Considerations:**
- This is not a replacement for firewall rules
- Combine with other security measures:
  - Pod Security Standards
  - RBAC
  - Service mesh policies
  - Cloud provider security groups
- Regularly audit external access requirements
- Monitor for policy violations

**GKE Specific Notes:**
- Requires GKE version 1.8.4-gke.0 or later
- GKE cluster CIDR is typically 10.0.0.0/8 or 10.4.0.0/14
- Check with: `gcloud container clusters describe <cluster> --format="value(clusterIpv4Cidr)"`
- Consider GKE Dataplane V2 for better performance

**Determining Cluster CIDR:**
```bash
# Method 1: Check cluster info
kubectl cluster-info dump | grep -i "cluster-cidr"

# Method 2: Check node pod CIDR
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'

# Method 3: Check service CIDR
kubectl cluster-info dump | grep -i "service-cluster-ip-range"

# Method 4: GKE specific
gcloud container clusters describe <cluster-name> --format="value(clusterIpv4Cidr,servicesIpv4Cidr)"

# Method 5: EKS specific
aws eks describe-cluster --name <cluster-name> --query cluster.kubernetesNetworkConfig
```

**Advanced Patterns:**

**Multi-Region Cluster:**
```yaml
egress:
# Allow internal cluster (all regions)
- to:
  - ipBlock:
      cidr: 10.0.0.0/8
  - ipBlock:
      cidr: 172.16.0.0/12
  - ipBlock:
      cidr: 192.168.0.0/16
```

**Hybrid Cloud:**
```yaml
egress:
# Internal cluster
- to:
  - ipBlock:
      cidr: 10.0.0.0/8
# On-premises datacenter
- to:
  - ipBlock:
      cidr: 172.20.0.0/16
  ports:
  - port: 1521  # Oracle DB
  - port: 3306  # MySQL
```

**Service Mesh Integration:**
When using a service mesh (Istio, Linkerd), NetworkPolicies work alongside service mesh policies:
- NetworkPolicy operates at L3/L4 (IP/port level)
- Service mesh operates at L7 (application level)
- Both are enforced - most restrictive wins
- Use NetworkPolicy for broad restrictions
- Use service mesh for fine-grained L7 policies

**Performance Considerations:**
- Egress policies can impact network performance
- Test latency after applying policies
- Monitor for increased connection setup time
- Consider policy complexity vs. performance trade-offs

**Monitoring:**
```bash
# Monitor denied connections (CNI dependent)
# Calico example:
kubectl logs -n calico-system -l k8s-app=calico-node | grep denied

# Cilium example:
cilium monitor --type drop --related-to <pod-name>

# Check NetworkPolicy status
kubectl get networkpolicy -o yaml

# View logs from affected pods
kubectl logs <pod-name> | grep -i "connection\|timeout\|refused"
```

This pattern is essential for implementing defense-in-depth security by preventing unauthorized external communication while maintaining necessary internal cluster connectivity.
