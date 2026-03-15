+++
title = "Bootstrap Cluster"
weight = 10
description = "Provisioning a brand-new cluster from scratch"
+++

Full sequence for provisioning a new BeCloudLess Kubernetes cluster from bare metal.

## Prerequisites

- At least one machine with a fresh NixOS install using the `serverKube` role
- `bcl` CLI available (`nix develop`)
- Git access to the repository
- Secrets backend configured (SOPS age key or Vault)

---

## Step 1 — Install NixOS on Nodes

For each node:

```bash
bcl nixos install <hostname>
```

This runs `nixos-anywhere` to partition, format, and install NixOS using the machine's configuration from the flake.

After the first boot, verify:

```bash
ssh root@<hostname> nixos-version
```

---

## Step 2 — Verify Kubernetes Node Readiness

```bash
kubectl get nodes
```

All nodes should be in `Ready` state before proceeding.

---

## Step 3 — Bootstrap Flux

```bash
bcl flux bootstrap
```

This installs Flux CD onto the cluster and points it at the `kube/` directory of the git repository.

---

## Step 4 — Verify Flux Reconciliation

```bash
flux get kustomizations --watch
```

Wait for all kustomizations to reach `Applied` / `Ready` state. This may take several minutes as container images are pulled.

---

## Step 5 — Verify Core Apps

```bash
kubectl get pods -A
```

Check that all pods in `cert-manager`, `cilium`, `flux-system`, and `longhorn-system` namespaces are running.

---

## Step 6 — Configure DNS

Point your domain's DNS records to the Traefik ingress IP/hostname. Run the Terraform OVH mail module if email is needed:

```bash
cd terraform
terraform apply
```

---

## Post-Bootstrap Checklist

- [ ] All Flux kustomizations are `Ready`
- [ ] cert-manager has issued certificates for all ingresses
- [ ] Longhorn dashboard is accessible
- [ ] Authelia and lldap are reachable
- [ ] Prometheus and Grafana are scraping metrics

