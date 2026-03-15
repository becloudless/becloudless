+++
title = "Adding a System"
weight = 40
description = "Step-by-step guide to onboarding a new machine"
+++

This guide walks through adding a new machine to BeCloudLess.

## 1. Create the Machine Directory

```bash
mkdir -p nixos/systems/x86_64-linux/<hostname>
```

Use `aarch64-linux` for ARM machines (e.g., OrangePi).

## 2. Create `default.nix`

```nix
# nixos/systems/x86_64-linux/<hostname>/default.nix
{ pkgs, lib, ... }:
{
  imports = [
    # Role — choose one
    ../../../modules/nixos/role/workstation.nix
    # ../../../modules/nixos/role/serverKube.nix

    # Hardware — choose if applicable
    # ../../../modules/nixos/hardware/devices/orangepi5plus.nix

    # Parts — add as needed
    ../../../modules/nixos/parts/wifi.nix
    ../../../modules/nixos/parts/sound.nix
  ];

  # Machine-specific overrides
  networking.hostName = "<hostname>";
}
```

## 3. Configure Disk Layout

If using disko for declarative disk partitioning, add a `disk.nix` alongside `default.nix`:

```nix
# nixos/systems/x86_64-linux/<hostname>/disk.nix
{ ... }:
{
  imports = [ ../../../modules/nixos/parts/disk.nix ];
  # disko device definitions here
}
```

## 4. Register in the Flake

Open `nixos/flake.nix` and add the machine to the `nixosConfigurations` attribute:

```nix
nixosConfigurations.<hostname> = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [ ./systems/x86_64-linux/<hostname> ];
};
```

## 5. Build and Deploy

```bash
# Dry-run to check for errors
nixos-rebuild dry-build --flake .#<hostname>

# Deploy to a remote machine
nixos-rebuild switch --flake .#<hostname> --target-host root@<hostname>

# Or use the bcl CLI
bcl nixos deploy <hostname>
```

## 6. (Optional) Add Hardware Module

If the machine uses a device not yet covered, add a hardware module under `nixos/modules/nixos/hardware/devices/`. See [Hardware — Adding a Device]({{< relref "docs/hardware/adding-hardware" >}}).

