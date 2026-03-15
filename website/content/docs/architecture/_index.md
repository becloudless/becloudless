+++
title = "Architecture"
weight = 20
description = "How NixOS, Kubernetes, CLI, and Terraform relate"
+++

## Overview

BeCloudLess is composed of four interconnected layers:

```text
┌─────────────────────────────────────────────────────┐
│                   bcl CLI                           │
│   (orchestrates all layers from a single tool)      │
└────────────┬──────────────┬──────────────┬──────────┘
             │              │              │
     ┌───────▼──────┐ ┌─────▼──────┐ ┌───▼────────┐
     │    NixOS     │ │ Kubernetes │ │ Terraform  │
     │  (machines)  │ │   (apps)   │ │ (cloud)    │
     └──────────────┘ └────────────┘ └────────────┘
```

## Layers

### NixOS — Machine Configuration

All physical and virtual machines (laptops, desktops, servers, TVs) are configured declaratively using NixOS. Configuration is structured around:

- **Roles** — high-level machine purpose (`workstation`, `serverKube`, `popKube`, `tv`, `install`)
- **Parts** — optional feature modules (`wifi`, `sound`, `bluetooth`, `docker`, `disk`, …)
- **Hardware** — device-specific configuration (`orangepi5`, `orangepi5plus`, …)
- **Global** — common settings applied to every machine

### Kubernetes — Application Platform

A GitOps-managed Kubernetes cluster running on `serverKube` nodes. Flux CD watches the `kube/` directory and reconciles the desired state. Apps are organised into:

- `kube/clusters/` — cluster-level bootstrap configuration
- `kube/groups/` — named groups of machines (`global`, `minimal`, `pop`, `server`)
- `kube/apps/` — individual application manifests

### CLI — `bcl`

A Go CLI that ties all layers together: provisioning NixOS systems, bootstrapping Flux, managing secrets, and interacting with the cluster.

### Terraform — Cloud Provisioning

Terraform modules for cloud resources that fall outside NixOS/Kubernetes (e.g., DNS, email via OVH).

## Data Flow

```text
Developer → git push
    → Flux detects change in kube/
    → Kubernetes reconciles apps
    → bcl CLI can also trigger NixOS rebuilds on individual nodes
```

## Key Design Decisions

- **Single repository** — all layers live together for atomic cross-layer changes.
- **Nix flakes** — reproducible, pinned dependency graph for all NixOS systems and the dev shell.
- **Flux GitOps** — Kubernetes desired state is always in git; no manual `kubectl apply`.
- **SOPS / external-secrets** — secrets are encrypted at rest in the repo and injected at runtime.

