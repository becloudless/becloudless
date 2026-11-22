---
name: bcl-kube-charts
description: "Use when: creating or changing Helm charts under kube/charts in becloudless (base library, base-loader, app-* app charts, postgresql, valkey, syncthing, restore-app), values, templates, CiliumNetworkPolicies, golden files ci/ci-result.yaml, helm template/unittest, `bcl k chart build`, app-bcl registry, sub-HelmReleases (-pre/-post/-integration), Flux HelmRelease values, Helm template errors (nil pointer, merge, dig, stale subchart tgz)."
---

# Kubernetes charts in bcl

Read [bcl-agent-workflow](../bcl-agent-workflow/SKILL.md) first. Helm template pitfalls: [references/helm-gotchas.md](./references/helm-gotchas.md). Live cluster work: [bcl-kube-operations](../bcl-kube-operations/SKILL.md). Changing the `base` library chart itself: [bcl-base-chart-internals](../bcl-base-chart-internals/SKILL.md). Per-app facts, SSO, Gateway API exposure: [bcl-app-charts](../bcl-app-charts/SKILL.md).
Reference docs: `website/content/docs/kubernetes/` (`app-charts.md` is the main one: sub-HRs, restore, values).

## Layout

- `kube/charts/base`: library chart that renders typed `resources` (deployments, services, certificates, HTTPRoutes, CNPs, ...). `resources.yaml` describes the kinds, `build/` generates `templates/resources/_renderResources.tpl` and the JSON schemas, mutations live in `templates/resources/mutations/*`.
- `kube/charts/base-loader`: renders the `resources` given in its values (used by sub-HRs). `kube/charts/app`: library for app charts (cluster values `app.domain`, ...).
- `kube/charts/app-<name>`: one chart per app, installed by `app-bcl` (registry in its `apps` values, groups `minimal`/`cluster`/`extra`, `clusterAdmin`, `restore: true`).
- Standalone reusable charts: `postgresql` (CloudNativePG), `valkey` (wraps the public chart through an OCI dependency), `syncthing`, `restore-app`.
- Per chart: `Chart.yaml`, `values.yaml`, `templates/`, `ci/ci-values.yaml` + `ci/ci-result.yaml` (golden render), `schema/` (editor schema), `tests/` (helm-unittest).

## Change a chart

1. Edit `values.yaml` / templates.
2. From the chart directory (not from `kube/charts`): `bcl k chart build`. It regenerates, runs unit tests and renders the CI cases against the goldens. `--validate` also dry-runs the render on the cluster you point at. If `base` changed, rebuild `base` first (`base/build.sh` regenerates schemas and `_renderResources.tpl`, `bcl k chart build` in `base` regenerates its goldens), then the charts that depend on it.
3. Read the golden diff (`git diff -- '*ci-result.yaml'`). Only charts you meant to change should move. When committed goldens are already ahead or behind their values (image bumps), do not regenerate everything: `git checkout -- <chart>/ci/ci-result.yaml` and patch only your change, or accept and mention the unrelated drift.
4. Never judge a looping CI script with `| tail` (see the workflow skill). Check the exit code or grep for `FAIL`.
5. Check `git status --short` in the chart: a stray untracked `.tpl` that re-`define`s a name of a tracked file, or an old pre-rename directory, silently shadows or breaks the build.
6. Public chart dependency: OCI `dependencies` work and Flux resolves them; `helm dependency update` in a copy, never keep a stale `charts/*.tgz` (see gotchas).

Do not edit generated files (`_renderResources.tpl`, schemas, goldens). Scripts embedded in `values.yaml` that are also copied in goldens (CronJob scripts) must stay identical in both. A script that grows should move to a `files/*.sh` rendered into a ConfigMap, with its hash in the Job name.

## Rules of the base chart

- Standard labels mutation: workloads and services get `app.kubernetes.io/name` (chart name), `instance` (release name), `component` (resource id) in labels, selectors and pod labels; user keys win. A Service for another workload uses `selector: {app.kubernetes.io/component: <id>}`. A selector is immutable: after changing it delete the Deployment/StatefulSet (`--cascade=orphan` for StatefulSets) and let Flux recreate it.
- Checksum mutation: Deployments/StatefulSets/DaemonSets get `checksum/configmaps|secrets` pod annotations from the ConfigMaps/Secrets of the same release they reference; others are read with `lookup` (empty in `helm template`). Jobs are not rolled by it.
- `templatedStrings`: string fields with enum/pattern/format also accept `{{ }}` in the editor schema. The schema is editor only: `helm template` does not reject bad values.
- `prefixNamesWithRelease` is false: resource names are the resource id. Resources go in the namespace of the HelmRelease: do not set namespaces in charts.
- Helm lists replace, they do not merge: override the whole list. `defaults` of an app are not inherited by instance/sub-HR releases (set them per release). The apps schema rejects `null` values.
- A subchart whose defaults contain nulls needs `checkRequiredValues: false`.
- A value starting with `{{ ... }}` must be quoted in YAML.

## Network policies (Cilium default deny)

- Baseline `default-deny` + `allow-dns` live in `app-cilium`; every other policy lives in the chart of the app and selects component labels, never `endpointSelector: {}`.
- Namespaced CNP `toEndpoints/fromEndpoints` mean same namespace unless `k8s:io.kubernetes.pod.namespace` is set. Jobs are selected with `job-name Exists`.
- Gateway traffic: `fromEntities: [ingress, host, remote-node]` (same node = `ingress`, other node = `remote-node`/`host`). Webhooks: `[apiserver, host, remote-node]`. Kubelet probes are always allowed.
- No `toEntities: world`: use `toFQDNs` with ports; it needs the DNS L7 rule in `allow-dns` and no CoreDNS `autopath`. `toFQDNs` and `toEntities` cannot share a rule: split them. A name served by the in-cluster Gateway is `toEntities: ingress`.
- Any app with a startup check to an external host (SMTP, NTP, OIDC issuer) needs an explicit egress rule, or it fails only after its pods restart.
- `postgresql` chart: `clients: {}` generates the CNP for port 5432. `valkey` chart: `clients` + `valkey.auth.aclUsers` (release name must contain `valkey`).
- Live testing of policies: Flux reverts live patches within 1-2 minutes; the extracted CI render uses a test domain, substitute your real one before applying.

## Adding an app (checklist)

Chart `app-<name>` with `app` + `base` dependencies, sub-HRs only when needed (`-pre` for what pods need at start, `-post` for CRD-based resources, `-integration` for exposure, never waited for), entry in the `app-bcl` registry, CNPs for each component, `restore: true` only for self-contained state (PVCs, CNPG, generated secrets), docs if the behaviour is new. Then build as above. Secrets that cannot be generated (SMTP passwords, OIDC client secrets) are created per cluster by the cluster owner: document the secret name and keys in the chart `values.yaml` header.
