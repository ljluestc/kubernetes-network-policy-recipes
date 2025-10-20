---
id: NP-00
title: Create Kubernetes Cluster with Network Policy Support
type: setup
category: infrastructure
priority: high
status: ready
estimated_time: 10m
dependencies: []
tags: [gke, kubernetes, network-policy, cluster-setup]
---

## Overview

Create a Kubernetes cluster with Network Policies feature enabled to support all subsequent network policy recipes and configurations.

## Objectives

- Provision a Kubernetes cluster with Network Policy support
- Configure Calico as the networking provider
- Validate cluster is ready for network policy deployments

## Background

Most Kubernetes installation methods do not provide a cluster with Network Policies feature enabled by default. Manual installation and configuration of a Network Policy provider (such as Weave Net or Calico) is typically required.

**Google Kubernetes Engine (GKE)** provides an easy path to get a Kubernetes cluster with Network Policies feature pre-configured. GKE automatically configures Calico as the networking provider (generally available as of GKE v1.10).

## Requirements

### Task 1: Create GKE Cluster with Network Policy
**Priority:** High
**Status:** pending

Create a GKE cluster named `np` with Network Policy feature enabled.

**Actions:**
- Run gcloud command to create cluster
- Enable network policy flag
- Specify zone for cluster deployment
- Create 3-node cluster configuration

**Command:**
```bash
gcloud container clusters create np \
    --enable-network-policy \
    --zone us-central1-b
```

## Acceptance Criteria

- [ ] GKE cluster created successfully with name `np`
- [ ] Network Policy feature enabled
- [ ] Calico networking provider configured
- [ ] 3-node cluster operational
- [ ] Cluster accessible via kubectl

## Technical Specifications

**Cluster Configuration:**
- Name: `np`
- Provider: Google Kubernetes Engine (GKE)
- Network Policy Provider: Calico
- Node Count: 3
- Zone: us-central1-b
- Kubernetes Version: v1.10+

## Verification

Verify cluster creation:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
```

## Cleanup

### Task: Delete Cluster
When tutorial is complete, remove the cluster:

```bash
gcloud container clusters delete -q --zone us-central1-b np
```

## References

- [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/)
- [Kubernetes Network Policies Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## Notes

This cluster serves as the foundation for all network policy recipes in this repository. Ensure this cluster is created before attempting any subsequent tutorials.
