+++
title = "Kubernetes"
weight = 40
description = "GitOps-managed cluster and applications"
+++

BeCloudLess manages a Kubernetes cluster using [Flux CD](https://fluxcd.io/) for GitOps reconciliation. All desired cluster state lives under `kube/`.

## Structure

```text
kube/
├── clusters/      # Cluster bootstrap — Flux install and source references
├── groups/        # Named groups of machines sharing a config set
│   ├── global/    # Applied to every node in the cluster
│   ├── minimal/   # Minimal base for edge/resource-constrained nodes
│   ├── pop/       # Pop nodes (popKube role)
│   └── server/    # Full server nodes (serverKube role)
└── apps/          # Individual application manifests (one directory per app)
```

## GitOps Model

Flux watches the `kube/` directory in the git repository. Any merged change is automatically reconciled onto the cluster — no manual `kubectl apply` is needed.

```text
git push → Flux source controller detects change
         → Kustomize controller applies manifests
         → Helm controller reconciles Helm releases
```

{{% children containerstyle="div" style="h2" description="true" %}}

