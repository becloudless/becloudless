+++
title = "Roles"
weight = 10
description = "High-level machine purposes"
+++

Roles define the high-level purpose of a machine. Each role enables a pre-defined set of services and default configuration. A machine has exactly one role.

Roles are defined under `nixos/modules/nixos/role/`.

## Available Roles

### `workstation`

A desktop or laptop for daily use. Enables a graphical environment, user-facing applications, printing/scanning, and optionally Bluetooth and Wi-Fi.

**Typical hardware:** laptop, desktop PC.

---

### `serverKube`

A Kubernetes worker/control-plane node. Enables CRI-O, kubeadm, Longhorn prerequisites, and high-availability keepalived. No graphical environment.

Related role modules: `serverKubeCrio`, `serverKubeCerts`, `serverKubeHap`.

**Typical hardware:** bare-metal server, NUC, OrangePi.

---

### `popKube`

A lightweight Kubernetes node intended for edge or resource-constrained environments (e.g., a single-board computer). Shares a subset of the `serverKube` configuration.

---

### `tv`

A living-room media machine. Enables a minimal graphical environment focused on media playback.

---

### `install`

A transient role used during the initial installation of a machine. Enables the installer environment and will be removed after the first boot into the target role.

## Role Configuration

Roles are activated by importing the corresponding module in the machine's system configuration:

```nix
# nixos/systems/x86_64-linux/myhostname/default.nix
{ ... }:
{
  imports = [ ../../../modules/nixos/role/workstation.nix ];
}
```

Global settings shared across all roles live in `nixos/modules/nixos/role/global/`. See [Global Config]({{< relref "global-config" >}}) for details.

