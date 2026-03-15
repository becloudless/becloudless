+++
title = "Parts"
weight = 20
description = "Optional feature modules"
+++

Parts are optional feature modules that can be mixed into any machine regardless of its role. They live under `nixos/modules/nixos/parts/`.

## Available Parts

| Part | File | Description |
|---|---|---|
| `bluetooth` | `bluetooth.nix` | Enables BlueZ and graphical Bluetooth manager |
| `boot` | `boot.nix` | Bootloader configuration (systemd-boot / GRUB options) |
| `dataBinds` | `dataBinds.nix` | Bind-mount external data directories into the system |
| `dataDisks` | `dataDisks.nix` | Additional data disk declarations and mount points |
| `disk` | `disk.nix` | Root disk partitioning and filesystem setup (disko) |
| `docker` | `docker.nix` | Docker daemon and rootless Docker for the main user |
| `printScan` | `printScan.nix` | CUPS printing and SANE scanning support |
| `sound` | `sound.nix` | PipeWire audio stack |
| `syncthing` | `syncthing.nix` | Syncthing continuous file synchronisation |
| `user` | `user.nix` | Main user account declaration and home-manager integration |
| `virtualbox` | `virtualbox.nix` | VirtualBox hypervisor |
| `wifi` | `wifi.nix` | NetworkManager Wi-Fi with iwd backend |
| `wm/` | `wm/` | Window manager configurations (see sub-directory) |

## Usage

Add the desired parts to a machine's `imports` list:

```nix
{ ... }:
{
  imports = [
    ../../../modules/nixos/role/workstation.nix
    ../../../modules/nixos/parts/bluetooth.nix
    ../../../modules/nixos/parts/sound.nix
    ../../../modules/nixos/parts/wifi.nix
  ];
}
```

## Window Managers (`wm/`)

The `wm/` sub-directory contains window manager-specific modules (e.g., GNOME, KDE, Hyprland). These are only meaningful on machines with the `workstation` role.

