---
id: NP-README
title: Kubernetes Network Policy Recipes
type: documentation
category: overview
priority: high
status: ready
estimated_time: 30m
dependencies: []
tags: [network-policy, kubernetes, security, documentation, recipes]
---

# Kubernetes Network Policy Recipes

![Build Status](https://github.com/ahmetb/kubernetes-networkpolicy-tutorial/workflows/Network%20Policy%20Tests/badge.svg)
![Test Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/ahmetb/kubernetes-networkpolicy-tutorial/badges/coverage.json)
![BATS Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/ahmetb/kubernetes-networkpolicy-tutorial/badges/bats-coverage.json)
![Tests](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/ahmetb/kubernetes-networkpolicy-tutorial/badges/tests.json)
![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)

## Overview

This repository contains various use cases of Kubernetes Network Policies and sample YAML files to leverage in your setup. If you ever wondered how to drop/restrict traffic to applications running on Kubernetes, this comprehensive guide provides practical recipes and patterns.

![Network Policy in Action](img/1.gif)
*You can get stuff like this with Network Policies...*

## Objectives

- Understand Kubernetes NetworkPolicy concepts and patterns
- Learn how to implement network segmentation in Kubernetes
- Apply zero-trust networking principles
- Secure cluster networking with practical examples
- Master ingress and egress traffic control

## Background

Easiest way to try out Network Policies is to create a new [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine) cluster. Applying Network Policies on your existing cluster can disrupt the networking. At the time of writing, most cloud providers do not provide built-in network policy support.

If you are not familiar with Network Policies at all, I recommend reading the article [Securing Kubernetes Cluster Networking](https://ahmet.im/blog/kubernetes-network-policy/) first.

## NetworkPolicy Crash Course

NetworkPolicies operate at layer 3 or 4 of OSI model (IP and port level). They are used to control the traffic in (ingress) and out (egress) of pods.

### NetworkPolicy Gotchas

- **Empty selector matches everything**: `spec.podSelector: {}` will apply the policy to all pods in the current namespace.

- **Selectors are namespace-scoped**: `spec.podSelector` of an ingress rule can only select pods in the same namespace as the NetworkPolicy.

- **Default allow all**: If no NetworkPolicies target a pod, all traffic to and from the pod is allowed. In other words, all traffic is allowed until a policy is applied.

- **No deny rules**: There are no explicit deny rules in NetworkPolicies. NetworkPolicies are deny-by-default, allow-explicitly. It's the same as saying "If you're not on the list you can't get in."

- **Empty rules block all**: If a NetworkPolicy matches a pod but has an empty/null rule, all traffic is blocked. Example:
  ```yaml
  spec:
    podSelector:
      matchLabels:
        app: web
    ingress: []  # Blocks all ingress
  ```

- **Policies are additive**: NetworkPolicies are additive. If multiple NetworkPolicies select a pod, their union is evaluated and applied to that pod. If ANY policy allows traffic, it flows.

## Repository Structure

### Before You Begin

I really recommend [watching my KubeCon talk on Network Policies](https://www.youtube.com/watch?v=3gGpMmYeEO8) if you want to get a good understanding of this feature. It will help you understand this repository better.

- [Create a cluster](00-create-cluster.md) - **NP-00**

### Basics

Core NetworkPolicy patterns for pod-level traffic control:

- [DENY all traffic to an application](01-deny-all-traffic-to-an-application.md) - **NP-01**
- [LIMIT traffic to an application](02-limit-traffic-to-an-application.md) - **NP-02**
- [ALLOW all traffic to an application](02a-allow-all-traffic-to-an-application.md) - **NP-02A**

### Namespaces

Namespace-level network segmentation patterns:

- [DENY all non-whitelisted traffic in the current namespace](03-deny-all-non-whitelisted-traffic-in-the-namespace.md) - **NP-03**
- [DENY all traffic from other namespaces](04-deny-traffic-from-other-namespaces.md) (a.k.a LIMIT access to the current namespace) - **NP-04**
- [ALLOW traffic to an application from all namespaces](05-allow-traffic-from-all-namespaces.md) - **NP-05**
- [ALLOW all traffic from a namespace](06-allow-traffic-from-a-namespace.md) - **NP-06**
- [ALLOW traffic from some pods in another namespace](07-allow-traffic-from-some-pods-in-another-namespace.md) - **NP-07**

### Serving External Traffic

Patterns for exposing services to external clients:

- [ALLOW traffic from external clients](08-allow-external-traffic.md) - **NP-08**

### Advanced

Advanced patterns for fine-grained control:

- [ALLOW traffic only to certain port numbers of an application](09-allow-traffic-only-to-a-port.md) - **NP-09**
- [ALLOW traffic from apps using multiple selectors](10-allowing-traffic-with-multiple-selectors.md) - **NP-10**

### Controlling Outbound (Egress) Traffic

Egress traffic control patterns:

- [DENY egress traffic from an application](11-deny-egress-traffic-from-an-application.md) - **NP-11**
- [DENY all non-whitelisted egress traffic in a namespace](12-deny-all-non-whitelisted-traffic-from-the-namespace.md) - **NP-12**
- [ALLOW egress traffic to specific pods](13-allow-egress-traffic-to-specific-pods.md) - **NP-13**
- [LIMIT egress traffic to the cluster (DENY external egress traffic)](14-deny-external-egress-traffic.md) - **NP-14**

**Coming Soon:**
- ALLOW traffic only to Pods in a namespace

## Quick Reference

### Policy Types by Use Case

**Security Posture:**
- Default Deny All: NP-01, NP-03, NP-11, NP-12
- Whitelisting: NP-02, NP-06, NP-07, NP-10
- External Access: NP-08

**Namespace Isolation:**
- Same Namespace Only: NP-04
- Cross-Namespace: NP-05, NP-06, NP-07

**Advanced Control:**
- Port-Level: NP-09
- Multiple Selectors: NP-10
- Egress Control: NP-11, NP-12, NP-13, NP-14

### Common Patterns

**Zero-Trust Foundation:**
1. Apply default-deny ingress (NP-03)
2. Apply default-deny egress (NP-12)
3. Whitelist necessary traffic explicitly

**Microservices Security:**
1. Limit traffic between services (NP-02)
2. Use multiple selectors for shared resources (NP-10)
3. Port-based segmentation (NP-09)

**Multi-Tenancy:**
1. Namespace isolation (NP-04)
2. Selective cross-namespace access (NP-06, NP-07)
3. External traffic control (NP-08)

## Prerequisites

- Kubernetes cluster v1.7+ with NetworkPolicy support
- Network plugin that implements NetworkPolicy (Calico, Cilium, Weave Net, etc.)
- kubectl configured to access your cluster
- Basic understanding of Kubernetes concepts

## Testing

This project has comprehensive automated testing with 100% recipe coverage.

### Quick Test

```bash
# Verify NetworkPolicy support
kubectl api-versions | grep networking.k8s.io/v1

# Check network plugin
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# Run all tests
cd test-framework
./run-all-bats-tests.sh
./run-integration-tests.sh
```

### Testing Infrastructure

- **115+ BATS unit tests** - Every recipe fully tested
- **25 integration tests** - Complex multi-policy scenarios
- **100% coverage** - All recipes have corresponding tests
- **5 CI/CD platforms** - GitHub Actions, GitLab CI, Jenkins, CircleCI, Azure Pipelines
- **Pre-commit hooks** - Automated quality checks

**See [TESTING.md](TESTING.md) for complete testing documentation.**

## Best Practices

1. **Start with Deny-All**: Begin with default-deny policies, then whitelist necessary traffic
2. **Label Consistently**: Use consistent labeling schemes across your applications
3. **Document Dependencies**: Maintain documentation of service dependencies
4. **Test Thoroughly**: Test policies in non-production before applying to production
5. **Monitor Traffic**: Use network flow logs to understand traffic patterns
6. **Progressive Rollout**: Apply policies gradually, starting with dev/staging
7. **Combine with RBAC**: Use NetworkPolicies alongside RBAC for defense-in-depth
8. **Regular Audits**: Periodically review and update policies

## Troubleshooting

### Policy Not Working
```bash
# Check if policy exists
kubectl get networkpolicy

# Describe policy details
kubectl describe networkpolicy <policy-name>

# Verify pod labels match
kubectl get pods --show-labels

# Check CNI plugin logs
kubectl logs -n kube-system -l k8s-app=<cni-plugin>
```

### Connection Issues
```bash
# Test connectivity from pod
kubectl exec -it <pod> -- wget -qO- --timeout=2 http://<service>

# Check DNS resolution
kubectl exec -it <pod> -- nslookup <service>

# Verify service endpoints
kubectl get endpoints <service>
```

### Common Issues
- CNI plugin doesn't support NetworkPolicy
- Labels don't match selectors
- Namespace not specified correctly
- DNS traffic not whitelisted
- Policies applied to wrong namespace

## Performance Considerations

- NetworkPolicies are evaluated at the CNI plugin level
- Large numbers of policies can impact performance
- Test scalability with your specific CNI plugin
- Monitor for increased latency after applying policies
- Consider policy complexity vs. performance trade-offs

## Security Considerations

NetworkPolicies are **defense-in-depth**, not a silver bullet:

- Combine with Pod Security Standards/Policies
- Use alongside RBAC for comprehensive access control
- Implement application-level authentication
- Use service mesh for L7 policies
- Monitor and log policy violations
- Regular security audits

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Quick Start for Contributors

```bash
# 1. Install pre-commit hooks (required)
pip install pre-commit
pre-commit install

# 2. Create your changes
# - Add or modify recipe file
# - Create BATS test for new recipes

# 3. Test locally
pre-commit run --all-files
cd test-framework && ./run-all-bats-tests.sh

# 4. Submit PR
git add .
git commit -m "Add/update recipe"
git push origin feature-branch
```

**Documentation:**
- [TESTING.md](TESTING.md) - Complete testing guide
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [docs/PRE_COMMIT.md](docs/PRE_COMMIT.md) - Pre-commit hooks guide

## Resources

### Official Documentation
- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy API Reference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#networkpolicy-v1-networking-k8s-io)

### Videos & Talks
- [KubeCon Talk: Securing Kubernetes Network](https://www.youtube.com/watch?v=3gGpMmYeEO8)
- [Securing Kubernetes Cluster Networking](https://ahmet.im/blog/kubernetes-network-policy/)

### Tools
- [Calico Network Policy Editor](https://editor.cilium.io/)
- [Network Policy Viewer](https://github.com/runoncloud/network-policy-viewer)

### CNI Plugins with NetworkPolicy Support
- [Calico](https://www.tigera.io/project-calico/)
- [Cilium](https://cilium.io/)
- [Weave Net](https://www.weave.works/oss/net/)
- [Antrea](https://antrea.io/)

## Community & Support

- **Issues**: Report issues or request features via [GitHub Issues](https://github.com/ahmetb/kubernetes-networkpolicy-tutorial/issues)
- **Discussions**: Join discussions on Kubernetes Slack #sig-network
- **Updates**: Star/watch this repository for updates

## License

Copyright 2017, Google Inc. Distributed under Apache License Version 2.0.
See [LICENSE](LICENSE) for details.

**Disclaimer:** This is not an official Google product.

## Acknowledgments

Created by Ahmet Alp Balkan ([@ahmetb](https://twitter.com/ahmetb)).

Special thanks to all contributors and the Kubernetes networking community.

---

![Stargazers over time](https://starcharts.herokuapp.com/ahmetb/kubernetes-networkpolicy-tutorial.svg)

## Quick Start Guide

### 1. Create Cluster
```bash
# GKE with Network Policy support
gcloud container clusters create np \
    --enable-network-policy \
    --zone us-central1-b
```

### 2. Apply Default-Deny
```bash
# Deny all ingress to namespace
kubectl apply -f 03-deny-all-non-whitelisted-traffic-in-the-namespace.md

# Deny all egress from namespace
kubectl apply -f 12-deny-all-non-whitelisted-traffic-from-the-namespace.md
```

### 3. Whitelist Required Traffic
```bash
# Allow specific services to communicate
kubectl apply -f 02-limit-traffic-to-an-application.md
```

### 4. Verify
```bash
# Check policies
kubectl get networkpolicy

# Test connectivity
kubectl run test --rm -i -t --image=alpine -- sh
```

Start with the recipes that match your use case and build from there!
