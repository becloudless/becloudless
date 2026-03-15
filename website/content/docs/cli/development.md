+++
title = "Development"
weight = 20
description = "Building and contributing to the CLI"
+++

## Prerequisites

- Go 1.21+
- `nix` (recommended — provides Go and all tools via `nix develop`)

## Project Layout

```text
cli/
├── main.go          # Entry point
├── go.mod           # Go module definition
├── go.sum
├── gomake           # Build helper script
├── assets/          # Embedded static assets
├── dist-tools/      # Distribution tooling
└── pkg/
    ├── bcl/         # Core bcl types and config loading
    ├── build/       # Image and artifact build logic
    ├── cmd/         # Cobra command definitions
    ├── docker/      # Docker client helpers
    ├── flux/        # Flux bootstrap and reconciliation
    ├── generated/   # Auto-generated code (do not edit manually)
    ├── git/         # Git operations
    ├── kube/        # Kubernetes client helpers
    ├── nixos/       # NixOS build and deploy logic
    ├── security/    # SOPS and secret management
    ├── system/      # System information
    ├── utils/       # Shared utilities
    └── version/     # Version embedding
```

## Building

```bash
cd cli
go build -o bcl .
```

Or via `gomake`:

```bash
./gomake build
```

## Running Tests

```bash
go test ./...
```

## Adding a New Command

1. Create a new file under `cli/pkg/cmd/` (e.g., `mycommand.go`).
2. Define a `cobra.Command` and register it with the parent command in `cmd/root.go`.
3. Implement business logic in the appropriate `pkg/<subsystem>/` package.
4. Add tests alongside the implementation.

## Code Generation

If the project uses code generation (e.g., for OpenAPI clients or CRD types), regenerate with:

```bash
./gomake generate
```

Generated files live in `cli/pkg/generated/` and must not be edited manually.

