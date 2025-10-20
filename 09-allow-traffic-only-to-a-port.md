---
id: NP-09
title: Allow Traffic Only to a Port of an Application
type: policy
category: advanced
priority: high
status: ready
estimated_time: 20m
dependencies: [NP-00]
tags: [network-policy, port-restriction, named-ports, metrics, monitoring]
---

## Overview

Create a NetworkPolicy that restricts ingress traffic to specific ports of an application, enabling fine-grained access control at the port level.

## Objectives

- Define ingress rules for specific ports
- Use both numerical and named ports in policies
- Allow monitoring access to metrics endpoints while restricting application access
- Understand port-based network segmentation

## Background

This NetworkPolicy lets you define ingress rules for specific ports of an application. If you do not specify a port in the ingress rules, the rule applies to all ports. A port may be either a numerical or named port on a pod.

**Use Cases:**
- Allow monitoring system to collect metrics by querying the diagnostics port without giving access to the application
- Enable health check probes to specific endpoints
- Restrict database access to specific port ranges
- Separate admin interfaces from user-facing interfaces

![Diagram of ALLOW traffic only to a port of an application policy](img/9.gif)

## Requirements

### Task 1: Deploy Multi-Port Application
**Priority:** High
**Status:** pending

Run a web server application that listens on multiple ports.

**Actions:**
- Deploy application pod with label `app=apiserver`
- Application responds on port 8000 for main traffic
- Application responds on port 5000 for metrics

**Command:**
```bash
kubectl run apiserver --image=ahmet/app-on-two-ports --labels="app=apiserver"
```

**Application Details:**
- Returns hello response on `http://:8000/`
- Returns monitoring metrics on `http://:5000/metrics`

### Task 2: Expose Application as Service
**Priority:** High
**Status:** pending

Create a Service to expose both application ports.

**Actions:**
- Create ClusterIP service for apiserver
- Map port 8001 to container port 8000
- Map port 5001 to container port 5000

**Command:**
```bash
kubectl create service clusterip apiserver \
    --tcp 8001:8000 \
    --tcp 5001:5000
```

**Important Note:**
Network Policies will not know the port numbers you exposed in the Service (8001 and 5001). This is because they control inter-pod traffic and when you expose a Pod as Service, ports are remapped. Therefore, you need to use the Pod port numbers (8000 and 5000) in the NetworkPolicy specification.

An alternative less error-prone approach is to refer to port names (such as `metrics` and `http`).

### Task 3: Create Port-Specific Policy
**Priority:** High
**Status:** pending

Create NetworkPolicy that allows traffic only to the metrics port from monitoring pods.

**Actions:**
- Create `api-allow-5000.yaml` manifest
- Configure port restriction for port 5000
- Allow traffic only from pods with `role=monitoring`
- Apply policy to cluster

**Manifest:** `api-allow-5000.yaml`
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: api-allow-5000
spec:
  podSelector:
    matchLabels:
      app: apiserver
  ingress:
  - ports:
    - port: 5000
    from:
    - podSelector:
        matchLabels:
          role: monitoring
```

**Key Configuration:**
- Targets pods with `app: apiserver` label
- Allows traffic only to port 5000
- Only from pods with `role: monitoring` label
- Drops all other traffic (including port 8000)

**Command:**
```bash
kubectl apply -f api-allow-5000.yaml
```

**Expected Output:**
```
networkpolicy "api-allow-5000" created
```

**Policy Effects:**
- Drops all non-whitelisted traffic to `app=apiserver`
- Allows traffic on port 5000 from pods with label `role=monitoring` in the same namespace
- Blocks traffic to port 8000 from all sources

### Task 4: Test Access Without Labels (Blocked)
**Priority:** High
**Status:** pending

Verify that traffic from pods without proper labels is blocked.

**Actions:**
- Run test pod without custom labels
- Attempt connection to both ports
- Confirm both connections are blocked

**Commands:**
```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://apiserver:8001
wget -qO- --timeout=2 http://apiserver:5001/metrics
```

**Expected Result:**
```
wget: download timed out
wget: download timed out
```

Both ports are blocked (pod doesn't have `role=monitoring` label)!

### Task 5: Test Access With Monitoring Label
**Priority:** High
**Status:** pending

Verify that monitoring pods can access port 5000 but not port 8000.

**Actions:**
- Run test pod with `role=monitoring` label
- Attempt connection to port 8000 (blocked)
- Attempt connection to port 5000 (allowed)
- Verify metrics response

**Commands:**
```bash
kubectl run test-$RANDOM --labels="role=monitoring" --rm -i -t --image=alpine -- sh
# Inside the pod:
wget -qO- --timeout=2 http://apiserver:8001
```

**Expected Result:**
```
wget: download timed out
```

Port 8000 is blocked (not in allowed ports)!

```bash
# Inside the same pod:
wget -qO- --timeout=2 http://apiserver:5001/metrics
```

**Expected Result:**
```
http.requests=3
go.goroutines=5
go.cpus=1
```

Port 5000 is accessible!

## Acceptance Criteria

- [ ] Multi-port application deployed with label `app=apiserver`
- [ ] Service exposes both ports (8001 and 5001)
- [ ] NetworkPolicy `api-allow-5000` created successfully
- [ ] Policy specifies port 5000 restriction
- [ ] Policy requires `role=monitoring` label
- [ ] Traffic to both ports blocked without proper labels
- [ ] Traffic to port 8000 blocked even with monitoring label
- [ ] Traffic to port 5000 allowed from monitoring pods
- [ ] Metrics endpoint accessible only to monitoring pods

## Technical Specifications

**NetworkPolicy Configuration:**
- Name: `api-allow-5000`
- Pod Selector: `app=apiserver`
- Allowed Port: 5000
- Source Selector: `role=monitoring`

**How It Works:**
- NetworkPolicy operates at pod level, not service level
- Port numbers in policy refer to container ports, not service ports
- When port is specified, only that port is whitelisted
- All other ports are implicitly denied
- The `from` selector further restricts which pods can access the port

**Port Specification:**
```yaml
# Numerical port
ports:
- port: 5000
  protocol: TCP

# Named port (preferred)
ports:
- port: metrics
  protocol: TCP
```

**Service vs Container Ports:**
```
Service Port 5001 → Container Port 5000
                    ↑
            NetworkPolicy checks this port
```

## Implementation Details

**Using Named Ports (Recommended):**

Named ports are less error-prone and more maintainable:

```yaml
# NetworkPolicy with named port
ingress:
- ports:
  - port: api-port
```

**Corresponding Pod Spec:**
```yaml
containers:
- name: api
  image: api-image:latest
  ports:
  - name: api-port
    containerPort: 5000
    protocol: TCP
```

**Benefits of Named Ports:**
- More readable and self-documenting
- Easier to change port numbers without updating policies
- Reduces configuration errors
- Better for multi-container pods

**Multiple Port Example:**
```yaml
spec:
  podSelector:
    matchLabels:
      app: myapp
  ingress:
  - ports:
    - port: 8080  # HTTP
    - port: 9090  # Metrics
    from:
    - podSelector:
        matchLabels:
          role: monitoring
  - ports:
    - port: 8080  # HTTP only
    from:
    - podSelector:
        matchLabels:
          role: frontend
```

**Different Rules for Different Ports:**
```yaml
spec:
  podSelector:
    matchLabels:
      app: database
  ingress:
  # Admin access to all ports
  - from:
    - podSelector:
        matchLabels:
          role: admin
  # App access only to port 5432
  - ports:
    - port: 5432
    from:
    - podSelector:
        matchLabels:
          role: application
```

**Protocol Specification:**
```yaml
ports:
- port: 5000
  protocol: TCP  # TCP (default), UDP, or SCTP

# Multiple protocols for same port
- port: 53
  protocol: UDP
- port: 53
  protocol: TCP
```

## Verification

Check policy and test connectivity:
```bash
# View NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy api-allow-5000

# View service and endpoints
kubectl get service apiserver
kubectl get endpoints apiserver

# Check pod ports
kubectl get pod -l app=apiserver -o jsonpath='{.items[0].spec.containers[0].ports}'

# Test from monitoring pod
kubectl run monitor --labels="role=monitoring" --rm -i -t --image=alpine -- sh
# Inside:
nc -zv apiserver 5000  # Should work
nc -zv apiserver 8000  # Should timeout

# Test from regular pod
kubectl run regular --rm -i -t --image=alpine -- sh
# Inside:
nc -zv apiserver 5000  # Should timeout
nc -zv apiserver 8000  # Should timeout
```

## Cleanup

### Task: Remove Resources
Remove all created resources:

```bash
kubectl delete pod apiserver
kubectl delete service apiserver
kubectl delete networkpolicy api-allow-5000
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Container Ports](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/)
- [Named Ports](https://kubernetes.io/docs/concepts/services-networking/service/#multi-port-services)

## Notes

**Best Practices:**
- Use named ports whenever possible for better maintainability
- Document which ports serve which purposes
- Separate administrative interfaces from user-facing ports
- Use different policies for different port access patterns
- Test all port combinations (allowed and blocked)

**Common Use Cases:**
```yaml
# Web application with separate admin interface
ingress:
# Public access to web port
- ports:
  - port: 80
    name: http
  from: []  # Allow from anywhere

# Admin access to admin port
- ports:
  - port: 8080
    name: admin
  from:
  - podSelector:
      matchLabels:
        role: admin
```

**Monitoring Pattern:**
```yaml
# Application with Prometheus metrics
ingress:
# App traffic from frontend only
- ports:
  - port: 8000
  from:
  - podSelector:
      matchLabels:
        tier: frontend

# Metrics from Prometheus only
- ports:
  - port: 9090
    name: metrics
  from:
  - namespaceSelector:
      matchLabels:
        name: monitoring
    podSelector:
      matchLabels:
        app: prometheus
```

**Database Pattern:**
```yaml
# PostgreSQL with separate replication port
ingress:
# Application queries
- ports:
  - port: 5432
  from:
  - podSelector:
      matchLabels:
        app: backend

# Replication traffic
- ports:
  - port: 5433
  from:
  - podSelector:
      matchLabels:
        role: postgres-replica
```

**Debugging Tips:**
```bash
# Check if container port is listening
kubectl exec -it <pod> -- netstat -tlnp

# Check if service maps to correct ports
kubectl describe service <name>

# View NetworkPolicy in detail
kubectl get networkpolicy <name> -o yaml

# Test specific port connectivity
kubectl run test --rm -i -t --image=nicolaka/netshoot -- bash
# Inside:
nc -zv <service> <port>
telnet <service> <port>
```

**Common Mistakes:**
- Using service ports instead of container ports in policy
- Forgetting to specify protocol (defaults to TCP)
- Not testing all combinations of ports and labels
- Confusing named ports with service port names
- Assuming port restrictions apply to service level

**Security Considerations:**
- Port-based segmentation is a defense-in-depth strategy
- Should be combined with application-level authentication
- Consider using mTLS for sensitive ports
- Monitor access to restricted ports
- Regularly audit port access policies

This pattern is essential for implementing the principle of least privilege at the network level, ensuring components can only access the specific ports they need.
