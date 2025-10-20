---
id: NP-08
title: Allow Traffic from External Clients
type: policy
category: basics
priority: high
status: ready
estimated_time: 15m
dependencies: [NP-00]
tags: [network-policy, external-traffic, load-balancer, ingress, allow-all]
---

## Overview

Create a NetworkPolicy that enables external clients from the public Internet (directly or via a Load Balancer) to access pods in a namespace that otherwise denies all non-whitelisted traffic.

## Objectives

- Enable external access to pods in a restricted namespace
- Configure NetworkPolicy to allow all sources
- Expose services via Load Balancer
- Understand how to whitelist external traffic

## Background

This NetworkPolicy enables external clients from the public Internet directly or via a Load Balancer to access pods. This is essential for exposing services to end users while maintaining network security policies.

**Use Cases:**
- Expose web applications to the public Internet in a namespace denying all non-whitelisted traffic
- Enable external access to API gateways in secured namespaces
- Allow Load Balancers to reach backend services
- Implement public-facing services while maintaining internal network restrictions

![Diagram of ALLOW traffic from external clients policy](img/8.gif)

## Requirements

### Task 1: Deploy and Expose Web Server
**Priority:** High
**Status:** pending

Run a web server and expose it to the internet with a Load Balancer.

**Actions:**
- Deploy nginx pod with label `app=web`
- Expose pod with LoadBalancer service type
- Wait for external IP assignment

**Commands:**
```bash
kubectl run web --image=nginx --labels="app=web" --port=80

kubectl expose pod/web --type=LoadBalancer
```

**Verification:**
Wait until an EXTERNAL-IP appears on `kubectl get service` output:

```bash
kubectl get service web -w
```

**Expected Output:**
```
NAME   TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)        AGE
web    LoadBalancer   10.0.0.123     35.123.45.67    80:32000/TCP   2m
```

### Task 2: Verify Initial External Access
**Priority:** High
**Status:** pending

Visit the external IP and confirm the service is accessible.

**Actions:**
- Retrieve external IP from service
- Access service via web browser or curl
- Confirm nginx welcome page loads

**Command:**
```bash
# Get the external IP
EXTERNAL_IP=$(kubectl get service web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test access
curl http://$EXTERNAL_IP
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

### Task 3: Create External Access Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that allows traffic from all sources (internal and external).

**Actions:**
- Create `web-allow-external.yaml` manifest
- Configure to allow all ingress traffic
- Apply policy to cluster

**Manifest:** `web-allow-external.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-external
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - {}
```

**Key Configuration:**
- Targets pods with `app: web` label
- Single ingress rule with empty selector
- No specific podSelector or namespaceSelector means allow from all sources
- Allows both cluster-internal and external traffic

**Command:**
```bash
kubectl apply -f web-allow-external.yaml
```

**Expected Output:**
```
networkpolicy "web-allow-external" created
```

### Task 4: Verify External Access Still Works
**Priority:** High
**Status:** pending

Confirm that external access continues to work after policy application.

**Actions:**
- Access external IP via browser or curl
- Verify nginx welcome page still loads
- Confirm no connection errors

**Command:**
```bash
curl http://$EXTERNAL_IP
```

**Expected Result:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

External access continues to work!

## Acceptance Criteria

- [ ] Nginx pod deployed with label `app=web`
- [ ] Service exposed as LoadBalancer type
- [ ] External IP assigned to service
- [ ] Service accessible from external clients before policy
- [ ] NetworkPolicy `web-allow-external` created successfully
- [ ] Policy allows traffic from all sources
- [ ] External access continues to work after policy application
- [ ] Internal cluster traffic also allowed

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `web-allow-external`
- Pod Selector: `app=web`
- Ingress Rules: Single empty rule allowing all sources

**How It Works:**
- The manifest specifies one ingress rule for `app=web` pods
- Since it does not specify a particular `podSelector` or `namespaceSelector`, it allows traffic from all resources
- Empty ingress rule `{}` means "allow from anywhere"
- This includes both external traffic and internal cluster traffic
- The policy whitelists all traffic sources

**Traffic Flow:**
```
External Client
       ↓
Load Balancer (External IP)
       ↓
Kubernetes Service (ClusterIP)
       ↓
NetworkPolicy (allows all sources)
       ↓
Pod (app=web)
```

**Important Notes:**
- This policy allows ALL traffic, both external and internal
- It's useful in namespaces with default-deny policies
- The Load Balancer handles external routing
- NetworkPolicy operates at the pod level, not service level

## Implementation Details

**Understanding Empty Ingress Rules:**

```yaml
# Allow from all sources (internal and external)
ingress:
- {}

# Equivalent to (but more concise than):
ingress:
- from: []  # Empty from array means "from anywhere"
```

**Port Restriction Example:**
To restrict external access only to port 80, you can deploy an ingress rule such as:

```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: web-allow-external-port-80
spec:
  podSelector:
    matchLabels:
      app: web
  ingress:
  - ports:
    - port: 80
      protocol: TCP
```

This allows traffic to port 80 from any source but blocks other ports.

**Multiple Port Example:**
```yaml
ingress:
- ports:
  - port: 80
    protocol: TCP
  - port: 443
    protocol: TCP
```

**Combining with Source Restrictions:**
```yaml
# Allow external traffic only to specific ports
# while blocking other traffic
ingress:
- ports:
  - port: 80
  - port: 443
# Note: no 'from' section means from anywhere
```

## Verification

Check policy and service configuration:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy web-allow-external

# View service details
kubectl get service web
kubectl describe service web

# Test internal access (from another pod)
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- http://web

# Test external access
curl http://$EXTERNAL_IP
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod web
kubectl delete service web
kubectl delete networkpolicy web-allow-external
```

**Note:** If using a cloud provider, ensure the Load Balancer is fully deleted to avoid charges:

```bash
# Verify Load Balancer is removed
kubectl get service
# Should not show the web service
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Services - LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)
- [Ingress vs LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## Notes

**Best Practices:**
- In production, prefer Ingress controllers over LoadBalancer for HTTP/HTTPS traffic
- Always use TLS/SSL for external traffic (port 443)
- Combine with other security measures (authentication, rate limiting)
- Consider using specific source IP ranges if possible (more restrictive)
- Monitor external access with logging and metrics

**Security Considerations:**
- This policy allows ALL traffic from any source
- Does not provide authentication or authorization
- Consider additional security layers:
  - WAF (Web Application Firewall)
  - DDoS protection
  - Rate limiting
  - Authentication at application level
  - TLS termination

**Alternative Approaches:**
```yaml
# Restrict to specific external IP ranges (CIDR blocks)
ingress:
- from:
  - ipBlock:
      cidr: 203.0.113.0/24
  ports:
  - port: 80

# Allow from Load Balancer source ranges
ingress:
- from:
  - ipBlock:
      cidr: 0.0.0.0/0
      except:
      - 169.254.169.254/32  # Block metadata service
  ports:
  - port: 80
```

**Cloud Provider Considerations:**
- **GKE:** Load Balancer automatically created
- **EKS:** Requires AWS Load Balancer Controller
- **AKS:** Azure Load Balancer automatically provisioned
- **On-premises:** May require MetalLB or similar

**Testing External Access:**
```bash
# Using curl
curl -v http://$EXTERNAL_IP

# Using wget
wget -O- http://$EXTERNAL_IP

# Check headers
curl -I http://$EXTERNAL_IP

# Test from different locations
curl http://$EXTERNAL_IP --resolve web.example.com:80:$EXTERNAL_IP
```

**Common Issues:**
- External IP pending: Wait for cloud provider provisioning
- Connection refused: Check pod is running and healthy
- Timeout: Verify firewall rules allow traffic to Load Balancer
- Policy not applied: Check podSelector matches pod labels

This pattern is essential for exposing public-facing services in Kubernetes while maintaining network security policies for internal traffic.
