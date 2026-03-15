+++
title = "Adding a Device"
weight = 20
description = "How to add a new hardware device module"
+++

This guide explains how to add support for a new hardware device under `nixos/modules/nixos/hardware/devices/`.

## When Is a Hardware Module Needed?

A hardware module is needed when a device requires:

- Out-of-tree kernel drivers or firmware
- Custom bootloader configuration (e.g., U-Boot for ARM SBCs)
- Device-specific kernel parameters or device tree overlays
- Non-standard disk/partition layout

Standard x86_64 hardware (common PCs, NUCs) typically doesn't need a dedicated hardware module — NixOS handles them automatically.

## 1. Create the Hardware Module

```bash
touch nixos/modules/nixos/hardware/devices/<device-name>.nix
```

Example skeleton for an ARM single-board computer:

```nix
# nixos/modules/nixos/hardware/devices/<device-name>.nix
{ pkgs, lib, ... }:
{
  # Boot
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Firmware / device tree
  hardware.deviceTree.enable = true;

  # Any required kernel modules
  boot.initrd.availableKernelModules = [ "... " ];
}
```

## 2. Register in `hardware/default.nix`

Open `nixos/modules/nixos/hardware/default.nix` and import the new file so it is discoverable:

```nix
{ ... }:
{
  imports = [
    ./devices/<device-name>.nix
  ];
}
```

## 3. Reference from a Machine

In the machine's system configuration, import the hardware module:

```nix
imports = [
  ../../../modules/nixos/hardware/devices/<device-name>.nix
];
```

## 4. Test

```bash
nixos-rebuild dry-build --flake .#<hostname>
```

Fix any evaluation errors before deploying to the target device.

## Existing Hardware Modules

| File | Device |
|---|---|
| `orangepi5.nix` | OrangePi 5 |
| `orangepi5plus.nix` | OrangePi 5 Plus |
| `orangepi5-common.nix` | Shared base for OrangePi 5 family |

See [OrangePi Setup]({{< relref "docs/hardware/orangepi" >}}) for the full OrangePi bring-up procedure.

