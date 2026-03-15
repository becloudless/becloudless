+++
title = "Adding an App"
weight = 50
description = "How to add a new Flux-managed application"
+++

This guide explains how to add a new Flux-managed application to the cluster.

## 1. Create the App Directory

```bash
mkdir kube/apps/<app-name>
```

## 2. Choose a Delivery Method

### Helm Release

Create a `HelmRelease` resource:

```yaml
# kube/apps/<app-name>/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: <app-name>
  namespace: <namespace>
spec:
  interval: 1h
  chart:
    spec:
      chart: <chart-name>
      version: "x.y.z"
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: flux-system
  values:
    # ...
```

### Plain Kustomize

Create a `kustomization.yaml` pointing to upstream manifests or local resources:

```yaml
# kube/apps/<app-name>/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
```

## 3. Add a Flux Kustomization

Create a Flux `Kustomization` to let Flux reconcile the app:

```yaml
# kube/apps/<app-name>/flux-kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app-name>
  namespace: flux-system
spec:
  interval: 10m
  path: ./kube/apps/<app-name>
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

## 4. Register with a Group

Add the app to the relevant group under `kube/groups/`:

```yaml
# kube/groups/server/kustomization.yaml
resources:
  # ...existing apps...
  - ../../apps/<app-name>/flux-kustomization.yaml
```

## 5. Handle Secrets

If the app needs secrets:

- Use `ExternalSecret` to pull from an external store, or
- Use `secret-generator` if a random value is sufficient.

Never commit plain-text secrets to the repository.

## 6. Commit and Push

```bash
git add kube/apps/<app-name>/ kube/groups/<group>/kustomization.yaml
git commit -m "feat(kube): add <app-name>"
git push
```

Flux will detect the change and reconcile the new app within its configured interval.

