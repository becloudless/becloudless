+++
title = "Disaster Recovery"
weight = 40
description = "Restoring from Longhorn backups or rebuilding the cluster"
+++

## Scenarios

1. [Restore a Longhorn Volume from Backup](#1-restore-a-longhorn-volume-from-backup)
2. [Recover a CloudNativePG Database](#2-recover-a-cloudnativepg-database)
3. [Rebuild the Cluster from Scratch](#3-rebuild-the-cluster-from-scratch)

---

## 1. Restore a Longhorn Volume from Backup

### Prerequisites

- Longhorn backup target (S3) is accessible
- The backup was created by Longhorn's scheduled backup policy

### Steps

1. Open the Longhorn UI (`https://longhorn.<domain>`).
2. Navigate to **Backup** → find the volume backup to restore.
3. Click **Restore** and choose a new volume name.
4. Update the `PersistentVolume` and `PersistentVolumeClaim` to reference the restored volume.
5. Restart the affected workload.

```bash
kubectl rollout restart deployment/<app-name> -n <namespace>
```

---

## 2. Recover a CloudNativePG Database

### Point-in-Time Recovery (PITR)

Edit the `Cluster` resource to enable recovery mode:

```yaml
spec:
  bootstrap:
    recovery:
      source: <backup-cluster-name>
      recoveryTarget:
        targetTime: "2026-03-14T10:00:00Z"  # adjust to desired point
  externalClusters:
    - name: <backup-cluster-name>
      barmanObjectStore:
        destinationPath: s3://<bucket>/<path>
        # credentials...
```

Apply and wait for the `Cluster` to reach `Ready` state.

---

## 3. Rebuild the Cluster from Scratch

{{% notice warning %}}
**Destructive** — only proceed if the cluster cannot be recovered in place.
{{% /notice %}}

### 3.1 — Restore NixOS on Nodes

Re-install NixOS on each node:

```bash
bcl nixos install <hostname>
```

### 3.2 — Bootstrap Flux

```bash
bcl flux bootstrap
```

### 3.3 — Restore Persistent Data

Restore Longhorn volumes from backups as described in [section 1](#1-restore-a-longhorn-volume-from-backup).

Restore PostgreSQL databases as described in [section 2](#2-recover-a-cloudnativepg-database).

### 3.4 — Verify

Follow the [Bootstrap Cluster]({{< relref "runbooks/bootstrap-cluster" >}}) post-bootstrap checklist to confirm all services are healthy.

