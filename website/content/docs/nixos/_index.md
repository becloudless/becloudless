+++
title = "NixOS"
weight = 30
description = "Managing physical machines with NixOS"
+++

BeCloudLess manages physical and virtual machines through a NixOS Nix flake located in `nixos/`.

## Structure

```text
nixos/
├── flake.nix            # Entry point — exposes all NixOS configurations
├── systems/             # Per-machine configuration files
│   └── x86_64-linux/
│       └── <hostname>/  # One directory per machine
├── modules/nixos/
│   ├── role/            # Machine roles (purpose)
│   ├── parts/           # Optional feature modules
│   ├── hardware/        # Device-specific drivers and settings
│   └── global/          # Settings applied to every machine
├── lib/                 # Shared Nix library functions
├── overlays/            # Nixpkgs overlays
├── packages/            # Custom packages
└── shells/              # Dev shells
```

{{% children containerstyle="div" style="h2" description="true" %}}

