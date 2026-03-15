+++
title = "Getting Started"
weight = 10
description = "Prerequisites, first clone, and bootstrap walkthrough"
+++

## Prerequisites

- A NixOS or Linux machine to act as the bootstrap host
- `nix` with flakes enabled (`experimental-features = nix-command flakes`)
- `git`
- `kubectl` and `flux` CLI (can be provided via the Nix dev shell)
- Access credentials for your cloud provider (if using Terraform)

## Clone the Repository

```bash
git clone https://gitea.example.com/bcl/becloudless.git
cd becloudless
```

## Development Shell

Enter the Nix dev shell to get all required tools:

```bash
nix develop
```

## Step 1 – Configure a NixOS Machine

1. Add your machine under `nixos/systems/x86_64-linux/<hostname>/`.
2. Assign a role (e.g., `workstation`, `serverKube`) in the system configuration.
3. Apply optional hardware and parts modules.

See [NixOS — Adding a System]({{< relref "docs/nixos/adding-a-system" >}}) for a detailed walkthrough.

## Step 2 – Bootstrap a Kubernetes Cluster

1. Provision one or more nodes running the `serverKube` NixOS role.
2. Use the `bcl` CLI to bootstrap Flux onto the cluster.
3. Flux will reconcile all apps defined under `kube/`.

See [Runbooks — Bootstrap Cluster]({{< relref "docs/runbooks/bootstrap-cluster" >}}) for the full sequence.

## Step 3 – Deploy Applications

Applications are managed via Flux and defined under `kube/apps/`. After the cluster is bootstrapped, Flux will automatically reconcile all enabled apps.

See [Kubernetes]({{< relref "kubernetes" >}}) for the full app inventory.

## Next Steps

- [Architecture]({{< relref "architecture" >}}) — understand the big picture
- [CLI Reference]({{< relref "docs/cli/commands" >}}) — explore all available commands
- [Runbooks]({{< relref "runbooks" >}}) — day-two operations

