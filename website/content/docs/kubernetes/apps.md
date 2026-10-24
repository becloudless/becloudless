+++
title = "Apps"
weight = 10
description = "Full inventory of managed applications"
+++

All applications are defined under `kube/apps/`, one directory per app.

## App Inventory

| App | Category | Description |
|---|---|---|
| `authelia` | Security | Single sign-on (SSO) and two-factor authentication proxy |
| `bcl` | Platform | BeCloudLess internal cluster services |
| `cert-manager` | Security | Automatic TLS certificate issuance (Let's Encrypt / internal CA) |
| `cert-manager-config` | Security | Issuers and ClusterIssuers for cert-manager |
| `cilium` | Networking | eBPF-based CNI, network policies, and kube-proxy replacement |
| `cnpg` | Storage | CloudNativePG operator for PostgreSQL clusters |
| `coredns` | Networking | Cluster DNS resolver |
| `descheduler` | Platform | Rebalances pods across nodes based on policy |
| `external-secrets` | Security | Syncs secrets from external stores into Kubernetes Secrets |
| `external-snapshotter` | Storage | CSI volume snapshot controller and CRDs |
| `firefox-sync` | Productivity | Self-hosted storage for Firefox Sync (Mozilla accounts, data on your own server) |
| `flux` | Platform | Flux CD GitOps controllers |
| `gitea` | DevOps | Self-hosted Git service and container registry |
| `homer` | Dashboard | Static application dashboard / home page |
| `immich` | Media | Self-hosted photo and video backup (Google Photos alternative) |
| `jellyfin` | Media | Self-hosted media server (Netflix alternative) |
| `kyverno` | Security | Kubernetes policy engine (admission controller) |
| `kyverno-config` | Security | Kyverno ClusterPolicies |
| `lldap` | Security | Lightweight LDAP server (user directory for SSO) |
| `longhorn` | Storage | Distributed block storage for Kubernetes |
| `longhorn-config` | Storage | Longhorn StorageClass and backup targets |
| `mailu` | Email | Self-hosted email stack (SMTP, IMAP, webmail) |
| `metrics-server` | Platform | Kubernetes resource metrics (used by HPA and `kubectl top`) |
| `multus` | Networking | Meta-CNI plugin for attaching multiple network interfaces to pods |
| `multus-config` | Networking | NetworkAttachmentDefinitions for Multus |
| `paperless` | Productivity | Document management with OCR and full text search (Paperless-ngx), SSO with Authelia |
| `prometheus` | Observability | Prometheus + Grafana monitoring stack |
| `renovate` | DevOps | Automated dependency update PRs |
| `seafile` | Productivity | Self-hosted file sync and share (Dropbox alternative), SSO with Authelia |
| `secret-generator` | Security | Generates random secrets and stores them as Kubernetes Secrets |
| `seerr` | Media | Overseerr/Jellyseerr media request management |
| `terraform` | Platform | Terraform runner for cloud resources |
| `traefik` | Networking | Ingress controller and reverse proxy |
| `traefik-config` | Networking | Traefik middlewares and IngressRoute defaults |
| `whoami` | Networking | Request echo server to check the Gateway, TLS and the Authelia forward auth headers |

## App Directory Layout

Each app directory typically contains:

```text
kube/apps/<app-name>/
├── kustomization.yaml     # Flux Kustomization or HelmRelease entry point
├── helmrelease.yaml       # Helm release definition (if Helm-based)
├── configmap.yaml         # App configuration
└── ...
```

