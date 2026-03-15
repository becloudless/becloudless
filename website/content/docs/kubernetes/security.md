+++
title = "Security"
weight = 40
description = "Authelia, lldap, external-secrets, Kyverno, cert-manager"
+++

## Stack Overview

| Component | App | Role |
|---|---|---|
| SSO / 2FA | `authelia` | Single sign-on proxy with TOTP/WebAuthn |
| User directory | `lldap` | Lightweight LDAP server |
| TLS certificates | `cert-manager` + `cert-manager-config` | Automatic certificate management |
| Secret sync | `external-secrets` | Pull secrets from external stores |
| Secret generation | `secret-generator` | Generate random secrets as Kubernetes Secrets |
| Policy engine | `kyverno` + `kyverno-config` | Admission control and policy enforcement |

## Authelia

Authelia is the SSO gateway. It sits in front of all HTTP services exposed via Traefik, requiring users to authenticate before reaching backend apps.

- **User store:** lldap (LDAP backend)
- **Session storage:** Redis
- **Config:** `kube/apps/authelia/`

## lldap

lldap provides a minimal LDAP server used as the user/group directory for Authelia and other LDAP-aware apps.

- Users and groups are managed via the lldap web UI.
- Config: `kube/apps/lldap/`

## cert-manager

cert-manager automates TLS certificate issuance and renewal. Supported issuers:

- **Let's Encrypt** (ACME DNS-01 challenge via Traefik / cloud DNS)
- **Internal CA** for cluster-internal services

`cert-manager-config` contains `ClusterIssuer` resources and default certificate templates.

## external-secrets

Syncs secrets from external secret stores (e.g., HashiCorp Vault, AWS Secrets Manager, a local SOPS-encrypted store) into native Kubernetes `Secret` objects.

- `ExternalSecret` resources reference keys in the external store.
- `SecretStore` / `ClusterSecretStore` resources configure the backend connection.

## secret-generator

Generates cryptographically random values and stores them as Kubernetes Secrets. Useful for initial passwords and tokens that don't need to be stored externally.

## Kyverno

Kyverno enforces cluster-wide policies:

- Require resource limits on all containers
- Prevent running containers as root
- Auto-inject common labels and annotations

`kyverno-config` contains the `ClusterPolicy` resources.

