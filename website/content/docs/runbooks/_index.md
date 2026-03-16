+++
title = "Runbooks"
weight = 80
description = "Operational procedures and troubleshooting"
+++

Runbooks document step-by-step operational procedures for common (and not-so-common) tasks.

## Conventions

- Commands are shown as `code blocks` — run them from the repository root unless noted otherwise.
- `<placeholder>` values must be substituted with your actual values.
- Steps marked **⚠️ destructive** will cause downtime or data loss if run incorrectly.

{{< cards >}}
  {{< card link="bootstrap-cluster" title="Bootstrap Cluster" >}}
  {{< card link="disaster-recovery" title="Disaster Recovery" >}}
  {{< card link="rotate-secrets" title="Rotate Secrets" >}}
  {{< card link="upgrade-nixos" title="Upgrade NixOS" >}}
{{< /cards >}}

