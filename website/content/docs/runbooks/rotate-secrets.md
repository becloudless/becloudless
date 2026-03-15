+++
title = "Rotate Secrets"
weight = 20
description = "Rotating SOPS keys or external-secrets backend credentials"
+++

## When to Use

- A SOPS age private key may have been compromised
- An external-secrets backend credential has expired or been rotated
- Regular security hygiene rotation

---

## Rotating a SOPS Age Key

### 1. Generate a New Key

```bash
age-keygen -o new-key.txt
```

Note the new public key from the output.

### 2. Update `.sops.yaml`

Replace the old public key with the new one:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: .*
    age: age1<new-public-key>
```

### 3. Re-encrypt All SOPS Files

```bash
find . -name '*.sops.*' -o -name '*.enc.*' | xargs -I{} sops updatekeys {}
```

### 4. Distribute the New Private Key

Store the new private key securely (password manager, hardware token). Remove the old key from all machines and CI environments.

### 5. Update CI Secret

Update the `SOPS_AGE_KEY` (or equivalent) secret in your CI/CD system with the new private key.

---

## Rotating an External-Secrets Backend Credential

### 1. Rotate the credential at the source

Rotate the credential in the external store (Vault, cloud provider, etc.).

### 2. Update the Kubernetes Secret

Update the `SecretStore` or `ClusterSecretStore` credential secret:

```bash
kubectl create secret generic <store-secret> \
  --from-literal=token=<new-token> \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3. Force Refresh

```bash
kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite
```

### 4. Verify

```bash
kubectl get externalsecrets -A
```

All `ExternalSecret` resources should show `SecretSynced`.

