---
name: bcl-base-chart-internals
description: "Use when: changing the bcl `base` library chart itself (kube/charts/base): resources.yaml kinds (adding a CRD-backed kind such as referenceGrants, tcpRoutes, serviceMonitors, validatingPolicies, verticalPodAutoscalers, externalSecrets), the build/ generator and its mutations (arraysToMaps, templatedStrings, standardLabels, checksums, mapsToArrays), templates/lib, helm-unittest or ci/run.sh of a library chart, server-side validation, resource-name rules, sprig merge/dig pitfalls, stray duplicate template files after a rename."
---

# Changing the `base` chart

Read [bcl-kube-charts](../bcl-kube-charts/SKILL.md) first for the build loop. This skill covers the chart internals. Older notes and goldens may call the chart `resources` or `base-resources` (previous names).

## Layout and generation

- `resources.yaml` lists every supported kind with its schema source (CRD URL, file and `kind:` filter, or a Kubernetes OpenAPI definition). Entries never carry a hand-written `required:` list: the generator derives required fields from the fetched schema. A CRD file with several documents (e.g. VPA ships three CRDs) is isolated by the `kind:` filter; check the generated schema description to be sure the right one was picked.
- `build/` (Go, `base/build.sh` or `go run .`) generates `templates/resources/_renderResources.tpl` (tracked, huge, never print or hand-edit) and the schemas (`schema/resources/*` and `values.schema.json` are gitignored). Regenerate with `base/build.sh`; `bcl k chart build` in `base` also regenerates its goldens. A full base build takes minutes, plan for it.
- The generator call that writes the chart-root `values.schema.json` is disabled on purpose (slow). Do not re-enable it; if a real need appears, do it as a one-off and ask first.
- Runtime pipeline per resource (`templates/resources/_renderResource.tpl`): defaults, metadata, mapsToArrays, content, then mutations (standardLabels, checksums, ...). A mutation that only applies to some kinds checks `.kind` inside the mutation.
- Schema mutations run at generation time (`build/pipeline.go`): `arraysToMaps` turns every array-of-objects field of every kind into an id-keyed map (users write `ports.main: {...}`), `templatedStrings` lets constrained string fields also accept `{{ }}` (editor validation only), `additionalPropertiesFalse`.

## arraysToMaps has a runtime reversal

Any array-of-object field (ports, containers, env, volumes, RBAC subjects...) is a map in values and must be turned back into a list when rendering. The generator records the converted dotted schema paths and `templates/mutations/_mapsToArrays.tpl` converts them back, sorted by key (no stable order existed). If a rendered manifest shows a map where Kubernetes expects a list, look there first. Plain `helm template` and helm-unittest never catch it because they do not validate against Kubernetes schemas.

## Validation facts

- Helm's `--validate` / dry-run install does not send objects to the API server (lenient client-side check only). Real validation is a server-side dry-run per object (`cli/pkg/kube/helm/chart.go`, `validateServerSide`, used by `bcl k chart build --validate`). The namespace must exist on the cluster; a NotFound on create is treated as an environment gap (skip + warn), like missing CRDs.
- Names built from `resources.<kind>.<id>` must be DNS-1123 labels: ids are kebab-case lowercase (`templates/lib/_computeName.tpl` fails on anything else, and on > 63 chars). Ids fully overridden by `nameOverride`/`fullNameOverride` are exempt.
- Admission webhooks reject CI fixtures with fake data: cert-manager `CertificateRequest.spec.request` is base64 of a PEM CSR while `Order.spec.request` is base64 of raw DER (use real throwaway CSRs); Longhorn `Setting` names must be real setting names (`fullNameOverride: default-replica-count`).

## Test harness for a library chart

A `type: library` chart cannot be rendered or unit-tested standalone (`library charts are not installable`, every helm-unittest suite fails with `template ... loader.yaml not exists or not selected`). `ci/run.sh` and `tests/run.sh` build a throwaway wrapper chart. To run a suite by hand:

```bash
tmp=$(mktemp -d); mkdir -p "$tmp/charts" "$tmp/tests" "$tmp/templates"
cp -r "$chart_dir" "$tmp/charts/<chartname>"
rm -rf "$tmp/charts/<chartname>"/{ci,generate,build,tests}     # the subchart's own tests/ must go too
cp "$chart_dir"/tests/*.yaml "$tmp/tests/"
# Chart.yaml with dependencies: file://charts/<chartname>, templates/loader.yaml: {{ include "<chartname>.loader.all" . }}
(cd "$tmp" && helm dependency update . && helm unittest .)
```

Do all of it in one terminal call with a generous timeout (a variable like `$tmp` is lost when a long call is moved to the background).

The wrapper chart name is hardcoded in both scripts and must match the `# Source:` lines of the goldens (`base-resources-test` after the rename). A stale name made every CI case fail while `| tail -5` showed trailing PASS lines: judge these runs by exit code or `grep -c '^FAIL'`, never by `tail`.

## Template pitfalls (sprig)

- `merge dst (dict "k" default)` is not "set if absent": zero values in `dst` (`false`, `""`, `0`, `{}`) count as unset and are overwritten (this turned `contentIsSpec: false` into `true`, wrapping ConfigMap data in `spec:`). Use `if not (hasKey $ctx "k")` + `set`. `merge` also mutates `dst` in place; copy with `merge dict .` (empty `dict` as destination keeps zero values).
- `dig` needs a plain `map[string]interface{}` as its last argument. The root `.Values` is `chartutil.Values` and fails with `interface conversion`. Dot-access one level first (`$root.Values.defaults | default dict`) or `toYaml | fromYaml` the whole thing.
- Defining the same `{{- define "name" }}` in two files is silent: the last parsed wins. Before editing a `.tpl`, `git status --short templates/` for `??` files and grep for other `define "<same name>"` in the chart. A top-level stray `_computeMetadata.tpl` (untracked, pre-refactor content) kept reappearing and failed with `no template "...computeName" associated with template gotpl`: delete it.
- After any directory or package rename (build/ -> generate/ -> build/, `resources` -> `base-resources`), stale old-name directories can reappear on disk later in the session (they show as `??` siblings with the OLD name, or as modified files matching an older state). Re-run `ls`, `git status --short` and the Go build after notices that files were edited externally. Diff before deleting a suspected stale directory, do not assume.
- Duplicate byte-identical files left by an incomplete `git mv` (`_content_test.yaml` in two directories) exist: compare before deleting.

## Adding a kind to resources.yaml

1. Add the entry (CRD URL or file + `kind:`; singular kind names for some CRDs such as `ValidatingPolicy`).
2. Add a CI values file `ci/rs-<kind>-values.yaml` (real, admission-valid sample data).
3. `base/build.sh`, then `bcl k chart build` in `base`; then rebuild dependents and read the golden diff.
4. If a kind is requested but no CRD source can be found after a few targeted searches (repos of the likely project), ask the user which project ships it instead of searching further.

## Mutations in short

- standardLabels: workloads and Services get `app.kubernetes.io/name` (chart name), `instance` (release), `component` (id), user keys win; releases of `base-loader` get name `base-loader`. Cilium policies on own pods select `instance` = HelmRelease name + `component` = id (cross namespace with the `k8s:` prefix). Public-chart pods keep their own labels. To verify inner renders, `helm template` the `base-loader` chart with the HelmRelease values from the app golden (the app golden shows HelmRelease values, not pods), after rebuilding `base-loader` to repack the base tgz.
- checksums: Deployment/StatefulSet/DaemonSet only, annotations `checksum/configmaps` and `checksum/secrets`, user annotations win, ConfigMaps/Secrets of the same release plus `lookup` for external names (empty in `helm template`, evaluated on Flux upgrade only, not on a secret-only change). Test with `ci/checksums-values.yaml`.
- externalSecrets kind exists (SecretStore / ExternalSecret) with its own CI values.
