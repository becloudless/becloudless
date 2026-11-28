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
| `bcl repository nixos system add <name> --group <group>` | Create `nixos/systems/<architecture>/<name>/default.nix` in the repository of the current directory. Flags: `--architecture` (default `x86_64-linux`), `--hardware`, `--device` (repeatable), `--motherboard-uuid`, `--mac` (repeatable). An existing system is never overwritten; `git add` the file, flakes ignore untracked files |
| `bcl repository nixos group add <name>` | Create `nixos/modules/nixos/groups/<name>/` in the repository of the current directory: the group module (`--role` sets the role of the group), a `.sops.yaml` and a `default.secrets.yaml` holding new ssh host keys, encrypted with sops for you and for the group. An existing group is never overwritten; `git add` the files, flakes ignore untracked files |
| `bcl repository nixos hardware create [name]` | Create `nixos/modules/nixos/hardware/<name>/default.nix` in the repository of the current directory. With the ssh flags (`--host`, `--user`, ...), the initrd and kernel modules and the `intel` common are deduced from `nixos-generate-config` run on that machine, and the name defaults to its product name. Without a host, an empty module is created. An existing hardware is never overwritten; reference it with `bcl repository nixos system add --hardware <name>` |

---

## `bcl nixos`

Manage NixOS machines.

| Command | Description |
|---|---|
| `bcl nixos build <hostname>` | Build the NixOS configuration without deploying |
| `bcl nixos deploy <hostname>` | Deploy (switch) the NixOS configuration to the target host |
| `bcl nixos install --host <host>` | Bootstrap NixOS onto a fresh machine (runs nixos-anywhere). Flags: `--system` (name of the system, otherwise found with the optional `bcl.system.id` or asked), `--yes` (skip the confirmation that precedes erasing the disks) |

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

