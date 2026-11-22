+++
title = "Commands"
weight = 10
description = "All commands grouped by subsystem"
+++

## Global Flags

| Flag | Description |
|---|---|
| `--help` | Show help for any command |
| `--debug` | Enable debug logging |

---

## `bcl repository` (alias `bcl repo`)

Handle the infrastructure repository.

| Command | Description |
|---|---|
| `bcl repository init [directory]` | Initialize an infrastructure repository in the directory (current by default): git, `nixos/flake.nix`, `.sops.yaml` with your age key, `kube/clusters/.env`, `.gitignore`. Existing files are never overwritten |

---

## `bcl nixos`

Manage NixOS machines.

| Command | Description |
|---|---|
| `bcl nixos build <hostname>` | Build the NixOS configuration without deploying |
| `bcl nixos deploy <hostname>` | Deploy (switch) the NixOS configuration to the target host |
| `bcl nixos install <hostname>` | Bootstrap NixOS onto a fresh machine (runs nixos-anywhere) |

---

## `bcl kube`

Interact with the Kubernetes cluster.

| Command | Description |
|---|---|
| `bcl kube status` | Show cluster and Flux reconciliation status |
| `bcl kube kubeconfig` | Fetch and merge kubeconfig for the cluster |

---

## `bcl flux`

Manage Flux GitOps reconciliation.

| Command | Description |
|---|---|
| `bcl flux bootstrap` | Bootstrap Flux onto the cluster from the git repository |
| `bcl flux reconcile` | Force an immediate reconciliation of all Flux kustomizations |

---

## `bcl build`

Build artifacts (container images, packages).

| Command | Description |
|---|---|
| `bcl build image <name>` | Build and push a container image from `docker/` |

---

## `bcl security`

Secret and certificate management.

| Command | Description |
|---|---|
| `bcl security sops edit <file>` | Decrypt and open a SOPS-encrypted file in `$EDITOR` |
| `bcl security sops encrypt <file>` | Encrypt a plain-text file with SOPS |

---

## `bcl system`

System-level utilities.

| Command | Description |
|---|---|
| `bcl system info` | Print versions of all managed components |

---

## `bcl version`

Print the `bcl` version.

```bash
bcl version
```

