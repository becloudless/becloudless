+++
title = "App Charts"
weight = 60
description = "Helm chart layout of the apps installed by the apps chart"
+++

Apps are Helm charts `kube/charts/app-<name>`, built on the `base` library chart and installed by the `apps` chart.
This page describes how an app chart splits its resources in several `HelmRelease`s (sub-HRs) so that they are
created in the right order.

## Installation

The `apps` chart (`kube/charts/apps`) has a registry of apps in its `apps` values, each in one or more groups
(`minimal`, `cluster`, `extra`). For each enabled app it creates:

- the namespace of the app, `<name>` by default (`namespace:` to change it)
- the service account `flux-<name>`, cluster-admin on the namespace of the app only
  (`clusterAdmin: true` for an app that installs cluster-scoped resources: CRDs, ClusterRoles, webhooks, ClusterIssuers...)
- the `HelmRelease` `app-<name>` installing `kube/charts/<appChart.name>` as `flux-<name>`

The resources of the chart are created in the namespace of its `HelmRelease`, so charts do not set a default
namespace. Resource names are the id of the resource: `prefixNamesWithRelease` is `false` by default in `base`.

## Sub-HRs

A chart does not create everything in its own release. A resource that needs something that does not exist yet
(a secret, a CRD, a running service) goes in a sub-HR created by the chart, which waits for it with `dependsOn`.
A sub-HR is either a chart of its own (`postgresql`, a chart of this repository) or `./kube/charts/base-loader`,
which renders the `resources` given in its `values`.

| HR | Contains | Waits for | Waited for |
|---|---|---|---|
| `<app>-pre` | what the service needs to start: generated secrets (`stringSecrets`), certificates mounted by the pods, Kyverno policies | external apps (`app-cert-manager`, `app-secret-generator`, `app-kyverno`...) | yes |
| `<app>` | the service: public Helm chart, or `configMaps`, `deployments`, `services`, `persistentVolumeClaims` through `base-loader` | `<app>-pre`, `<app>-postgresql`, `<app>-valkey` | yes |
| `<app>-post` | resources of the CRDs declared by the service (Longhorn settings and storage classes, cert-manager ClusterIssuers, Kyverno policies, Cilium Gateway...) | `<app>` | yes |
| `<app>-integration` | public exposure: gateway certificate, `listenerSets`, `httpRoutes`, `tlsRoutes`, `referenceGrants` | `<app>-post` or `<app>`, `app-cert-manager`, `app-gateway-api` | no |

Rules:

- The service always starts after `-pre`: what a pod mounts or reads at start (a secret, a certificate) is in `-pre`,
  never in the service or in `-integration`.
- `-post` always starts after the service, because the CRDs it needs come with it.
- `-integration` starts after `-post` (or the service when there is none), but nothing waits for it:
  `install.disableWait` and `upgrade.disableWait` are `true`. A slow or failing public part (a rate limited
  Let's Encrypt certificate, a route not accepted) does not keep `app-<name>`, and the apps depending on it, from being ready.
  Its state is visible on its own `HelmRelease`.
- Only create the sub-HRs the app needs. `-pre` and `-post` are only for apps that have something to put in them.
- A sub-HR that has to depend on an app does it with `dependsOn` in the chart, not in the `apps` chart.
- A certificate that a pod mounts (`tls-lldaps`) is in `-pre`, the one only used by the Gateway (`lldap-gateway`) is in `-integration`.
- The sub-HRs of an app run as `flux-<name>`, they can only create resources in the namespace of the app, except for
  apps with `clusterAdmin`.
- The postgres cluster of an app is a sub-HR `<app>-postgresql` (chart `postgresql`) depending on `app-cert-manager`,
  `app-cnpg` and `app-longhorn`. The chart sets `prefixNamesWithRelease: true`, its resources are named `<release>-<id>`.

```mermaid
flowchart LR
  ext["external apps<br/>cert-manager, secret-generator, kyverno"] --> pre
  pre["&lt;app&gt;-pre"] --> svc["&lt;app&gt;"]
  db["&lt;app&gt;-postgresql<br/>&lt;app&gt;-valkey"] --> svc
  svc --> post["&lt;app&gt;-post"]
  post -.-> integration["&lt;app&gt;-integration<br/>(not waited for)"]
  svc -.-> integration
```

## Example

`app-lldap`:

```yaml
resources:
  fluxHelmReleases:
    lldap-postgresql:            # the database
      chart:
        spec:
          chart: ./kube/charts/postgresql
          ...

    lldap-pre:                   # secrets and certificate mounted by the pod
      dependsOn:
        cert-manager: { name: app-cert-manager, namespace: cert-manager }
        secret-generator: { name: app-secret-generator, namespace: secret-generator }
      chart:
        spec:
          chart: ./kube/charts/base-loader
          ...
      values:
        resources:
          stringSecrets: ...
          certManagerCertificates: ...

    lldap:                       # the service
      dependsOn:
        lldap-pre: { name: lldap-pre }
        lldap-postgresql: { name: lldap-postgresql }
      ...
      values:
        resources:
          configMaps: ...
          deployments: ...
          services: ...

    lldap-integration:           # exposed by the Gateway, not waited for
      install:
        disableWait: true
      upgrade:
        disableWait: true
      dependsOn:
        lldap: { name: lldap }
        cert-manager: { name: app-cert-manager, namespace: cert-manager }
        gateway-api: { name: app-gateway-api, namespace: gateway-api }
      ...
      values:
        resources:
          certManagerCertificates: ...
          listenerSets: ...
          httpRoutes: ...
          tlsRoutes: ...
```

Apps that are only static resources (`homer`, `jellyfin`, `landing`, `seerr`) put them in the `<app>` sub-HR, so that
`<app>-integration` has a service to wait for. `app-longhorn` has the four: `longhorn-pre` (NixOS PATH policy), `longhorn`
(the Helm chart), `longhorn-post` (settings, recurring jobs, storage and snapshot classes) and `longhorn-integration` (the UI).

## Exceptions

- `flux-integration` (`app-flux`, disabled by default) and `kube-integration` (`app-kube`) only have the public part,
  without a `-pre`, a service or a `-post` sub-HR. They are not waited for either, and wait for `app-gateway-api`
  (and `app-cert-manager` for flux), which these apps are installed before.
- `cert-manager-post`, `kyverno-post` and `cilium-post` only have resources of the CRDs of the service.

## Checking a chart

```bash
cd kube/charts/app-<name>
bcl k chart build   # unit tests, schema validation, renders ci/*-values.yaml into ci/*-result.yaml
```

`ci/*-result.yaml` shows every HR with its `dependsOn` and `disableWait`.
