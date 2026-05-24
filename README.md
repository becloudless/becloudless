[![Release](https://github.com/becloudless/becloudless/actions/workflows/daily-release.yaml/badge.svg)](https://github.com/becloudless/becloudless/actions/workflows/daily-release.yaml)

# BeCloudLess

**BeCloudLess** is an opinionated, single-repository infrastructure framework that takes you from bare-metal hardware to a fully self-hosted, production-grade infrastructure using only free and open-source software — no cloud vendor required.

It acts as the glue between powerful FOSS tools (NixOS, Kubernetes, Flux CD, Terraform, SOPS…), wiring them together so that what looks like a complex infrastructure stack becomes a simple, reproducible, and maintainable system.

> BeCloudLess is in early development. It is used in production by the author, but the architecture is not stable yet and breaking changes can occur at any time. Stable architecture and self-migration tooling are planned for V1.

---

## What it does

BeCloudLess lets you:

- **Declaratively configure every machine** (laptops, desktops, servers, ARM boards, TVs, …) using NixOS.
- **Run a self-hosted Kubernetes cluster** on your own hardware, managed entirely with GitOps.
- **Deploy a full suite of self-hosted applications** (mail, photos, media, git, identity, monitoring, …) without touching a major cloud provider.
- **Provision supporting cloud resources** (DNS, email relay, …) via Terraform when needed.
- **Orchestrate everything** through the `bcl` CLI — a single tool that ties all layers together.

---

## Architecture

BeCloudLess is composed of four interconnected layers orchestrated by the `bcl` CLI:

```
┌─────────────────────────────────────────────────────┐
│                      bcl CLI                        │
│   (orchestrates all layers from a single tool)      │
└────────────┬──────────────┬──────────────┬──────────┘
             │              │              │
     ┌───────▼──────┐ ┌─────▼──────┐ ┌───▼────────┐
     │    NixOS     │ │ Kubernetes │ │ Terraform  │
     │  (machines)  │ │   (apps)   │ │  (cloud)   │
     └──────────────┘ └────────────┘ └────────────┘
```

### NixOS — Machine Configuration

All physical and virtual machines are configured declaratively with NixOS and Nix flakes. Machine configuration is structured around four building blocks:

| Concept | Description |
|---|---|
| **Roles** | High-level machine purpose: `workstation`, `serverKube`, `popKube`, `tv`, `install` |
| **Parts** | Optional feature modules: `wifi`, `sound`, `bluetooth`, `docker`, `disk`, … |
| **Hardware** | Device-specific configuration: `orangepi5`, `orangepi5plus`, … |
| **Global** | Common settings applied to every machine |

Systems are installed from scratch using [disko](https://github.com/nix-community/disko) for declarative disk partitioning, and secrets are managed with SOPS.

### Kubernetes — Application Platform

A GitOps-managed Kubernetes cluster runs on `serverKube` nodes. [Flux CD](https://fluxcd.io/) watches the `kube/` directory and continuously reconciles the desired state. The layout is:

- `kube/clusters/` — cluster-level bootstrap configuration
- `kube/groups/` — groups of machines (`global`, `minimal`, `pop`, `server`)
- `kube/apps/` — individual application manifests (Authelia, Gitea, Immich, Jellyfin, Mailu, Prometheus, Traefik, …)

Secrets are stored encrypted in the repository with SOPS and injected at runtime via [external-secrets](https://external-secrets.io/).

### CLI — `bcl`

A Go CLI that ties all layers together. Key capabilities:

- **NixOS**: install, upgrade, prepare systems; manage hardware configuration; build ISOs; edit global/group config
- **Kubernetes**: bootstrap Flux on a new cluster; manage contexts and secrets
- **Terraform**: run cloud provisioning workflows
- **Docker**: local container helpers
- **CI**: continuous integration utilities

### Terraform — Cloud Provisioning

Terraform modules manage cloud resources that fall outside NixOS/Kubernetes (e.g., DNS zones and email routing via OVH).

---

## How it works

```
Developer → git push
    → Flux detects change in kube/
    → Kubernetes reconciles apps
    → bcl CLI can also trigger NixOS rebuilds on individual nodes
```

1. All configuration lives in **a single repository** — enabling atomic cross-layer changes.
2. **Nix flakes** provide a reproducible, pinned dependency graph for all NixOS systems and the dev shell.
3. **Flux GitOps** keeps the Kubernetes desired state always in git — no manual `kubectl apply`.
4. **SOPS / external-secrets** ensure secrets are encrypted at rest in the repo and injected at runtime.

---

## Getting Started

### Prerequisites

- A NixOS or Linux machine to act as the bootstrap host
- `nix` with flakes enabled (`experimental-features = nix-command flakes`)
- `git`, `kubectl`, and `flux` (available via the Nix dev shell)

### Enter the dev shell

```bash
nix develop
```

### Add a NixOS machine

1. Add your machine under `nixos/systems/<arch>/<hostname>/`.
2. Assign a role (`workstation`, `serverKube`, …) and select the appropriate hardware and parts modules.
3. Deploy with: `bcl nixos install <hostname>` or `bcl nixos upgrade <hostname>`.

### Bootstrap a Kubernetes cluster

1. Provision one or more nodes with the `serverKube` NixOS role.
2. Bootstrap Flux: `bcl kube bootstrap`.
3. Flux will reconcile all apps defined under `kube/`.

---

## Key Design Decisions

- **Single repository** — all layers live together for atomic cross-layer changes.
- **Nix flakes** — reproducible, pinned dependency graph for all NixOS systems and the dev shell.
- **Flux GitOps** — Kubernetes desired state is always in git; no manual `kubectl apply`.
- **SOPS / external-secrets** — secrets are encrypted at rest in the repo and injected at runtime.
- **100% FOSS** — no proprietary software or cloud services required.
