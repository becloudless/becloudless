+++
title = "CLI"
weight = 50
description = "The bcl command-line tool"
+++

The `bcl` CLI is the single entry point for all BeCloudLess operations. It is written in Go and lives in `cli/`.

## Installation

### From Source (via Nix dev shell)

```bash
nix develop   # enters the dev shell with bcl on PATH
```

### Build Manually

```bash
cd cli
go build -o bcl .
```

Or use the included `gomake`:

```bash
cd cli
./gomake build
```

## Configuration

`bcl` reads its configuration from the repository root. Run commands from within the repository.

{{< cards >}}
  {{< card link="commands" title="Commands" >}}
  {{< card link="development" title="Development" >}}
{{< /cards >}}

