+++
title = "Networking"
weight = 20
description = "Cilium, CoreDNS, Multus, Traefik"
+++

## Stack Overview

| Component | App | Role |
|---|---|---|
| CNI | `cilium` | eBPF-based pod networking and network policies |
| DNS | `coredns` | Cluster-internal DNS resolution |
| Multi-NIC | `multus` + `multus-config` | Attach additional network interfaces to pods |
| Ingress | `traefik` + `traefik-config` | HTTP/HTTPS ingress and reverse proxy |

## Cilium

Cilium replaces kube-proxy entirely using eBPF. It provides:

- Pod-to-pod routing (VXLAN or native routing)
- Kubernetes `NetworkPolicy` enforcement
- `CiliumNetworkPolicy` for L7 policies
- Hubble for network observability

Configuration lives in `kube/apps/cilium/`.

## CoreDNS

Handles all `*.cluster.local` DNS resolution. The default CoreDNS config is overridden via the `coredns` app to add custom stub zones if needed.

## Multus

Multus allows pods to have secondary network interfaces (e.g., a dedicated VLAN, macvlan bridge). `NetworkAttachmentDefinitions` are managed in `kube/apps/multus-config/`.

## Traefik

Traefik acts as the cluster ingress controller. Key features used:

- Automatic TLS via cert-manager (Let's Encrypt)
- Middleware for authentication forwarding to Authelia
- `IngressRoute` CRDs for fine-grained routing

Default middlewares and IngressRoute templates are in `kube/apps/traefik-config/`.

