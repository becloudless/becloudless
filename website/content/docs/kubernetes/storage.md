+++
title = "Storage"
weight = 30
description = "Longhorn, CloudNativePG, snapshots"
+++

## Stack Overview

| Component | App | Role |
|---|---|---|
| Block storage | `longhorn` + `longhorn-config` | Distributed replicated block storage |
| PostgreSQL | `cnpg` | Managed PostgreSQL clusters |
| Snapshots | `external-snapshotter` | CSI volume snapshot support |

## Longhorn

Longhorn provides distributed block storage backed by node-local disks. It handles:

- Automatic replication across nodes
- Volume snapshots and backups (S3-compatible target)
- Live volume expansion

The `longhorn` app installs the operator. `longhorn-config` defines the default `StorageClass` and backup targets.

**Prerequisites on NixOS nodes:**
Nodes running the `serverKube` role include the required kernel modules and open-iscsi service.

### Backup Target

Configure an S3 backup target in `kube/apps/longhorn-config/` to enable scheduled off-cluster backups.

## CloudNativePG (CNPG)

CNPG manages PostgreSQL clusters as Kubernetes-native resources. Apps that require PostgreSQL (e.g., Gitea, Authelia) each declare a `Cluster` resource.

Features used:

- Streaming replication with automatic failover
- Scheduled WAL archiving to S3
- Point-in-time recovery

## External Snapshotter

Provides the `VolumeSnapshot` and `VolumeSnapshotContent` CRDs and the snapshot controller required by Longhorn and CNPG for CSI-based snapshots.

