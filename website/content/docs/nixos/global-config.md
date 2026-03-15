+++
title = "Global Config"
weight = 30
description = "Settings common to all machines"
+++

The global module (`nixos/modules/nixos/global/`) is automatically applied to every machine in the flake. It provides a minimal, opinionated baseline.

## Schema

Options are defined and validated against `nixos/modules/nixos/global/default.schema.json`. This JSON Schema documents every option exposed by the global module.

To view the schema:

```bash
cat nixos/modules/nixos/global/default.schema.json
```

## What the Global Module Configures

| Sub-module | File | Purpose |
|---|---|---|
| Auto-upgrade | `autoUpgrade.nix` | Periodic flake-based NixOS auto-upgrades |
| Garbage collection | `gc.nix` | Nix store GC schedule and keep settings |
| Networking | `networking.nix` | Hostname, firewall, and base network settings |
| Nix | `nix.nix` | Nix daemon settings, substituters, flake pins |
| Packages | `packages.nix` | Baseline system packages present on all machines |
| Persistence | `persistence.nix` | Impermanence / persistent directories (opt-in) |
| Prometheus | `prometheus.nix` | Node exporter for cluster-wide metrics scraping |
| SSH | `ssh.nix` | OpenSSH daemon and authorised keys |
| Swap | `swap.nix` | zram or disk swap configuration |
| System | `system.nix` | Timezone, locale, and state version |
| Users | `users.nix` | System-level user and group declarations |

## Overriding Global Options

Any global option can be overridden in a machine's own configuration file. NixOS module system merging rules apply — scalar values can be overridden, list values can be extended with `lib.mkForce` if needed.

