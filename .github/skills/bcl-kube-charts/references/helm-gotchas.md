# Helm and chart gotchas

## Stale packaged dependency

`helm dependency update` packs local `file://` dependencies into `charts/<dep>-<ver>.tgz`. `helm template/install` then reads only the tgz. Editing `charts/<dep>/` afterwards has no deterministic effect (sometimes the folder, sometimes the stale tgz). When iterating on a local library chart used as a dependency: `rm -rf charts/<dep> charts/<dep>-*.tgz`, copy the fresh chart, `helm dependency update .`.

## nil key through dot access

`$root.Values.foo.bar` fails with `nil pointer evaluating interface {}.bar` when `foo:` exists in `values.yaml` with no value (literal nil, not `{}`). Default the intermediate first: `$foo := $root.Values.foo | default dict`.

## sprig `merge` and zero values

`merge $dst $src` treats zero values already in `$dst` (`false`, `""`, `0`, `{}`) as unset and overwrites them with `$src`. So `merge . (dict "contentIsSpec" true)` turns an explicit `false` into `true`. To default a key only when absent: `{{- if not (hasKey $ctx "key") }}{{- $ctx = set $ctx "key" default }}{{- end }}`. `merge` also mutates its first argument in place (Go maps are references): copy first with `merge dict .` (empty `dict` as destination, so nothing is zero-valued there).

## sprig `dig` on `.Values`

`dig` needs a literal `map[string]interface{}`. The root `.Values` is a `chartutil.Values` and fails with `interface conversion`. Access one level first (`.Values.defaults | default dict`), or convert: `.Values | toYaml | fromYaml`.

## Duplicate `define`

Go templates allow redefining the same `{{ define "name" }}` in two files without error; the last parsed wins. A stray untracked file redefining a tracked helper (often a leftover of a rename) shows up as `no template "..." associated with template gotpl`. `git status --short templates/` and grep for the define name before assuming the file you were pointed at is the real implementation.

## Library charts cannot be rendered or unit-tested directly

`type: library` charts are not installable (`helm template .` fails) and `helm unittest .` fails every suite with `template ".../loader.yaml" not exists or not selected`. `ci/run.sh` and `tests/run.sh` build a throwaway wrapper chart. Recipe to run unit tests by hand, in ONE terminal call (shell variables are lost if the command moves to the background):

```bash
tmp=$(mktemp -d); mkdir -p "$tmp/charts" "$tmp/templates" "$tmp/tests"
# wrapper Chart.yaml with a file:// dependency on the library chart, templates/loader.yaml: {{ include "<lib>.loader.all" . }}
cp -r "$chart_dir" "$tmp/charts/<lib>"
rm -rf "$tmp/charts/<lib>/ci" "$tmp/charts/<lib>/generate" "$tmp/charts/<lib>/tests"   # the subchart's own tests/ must go too
cp "$chart_dir"/tests/*.yaml "$tmp/tests/"
(cd "$tmp" && helm dependency update . && helm unittest .)
```

The wrapper chart name hardcoded in `ci/run.sh` and `tests/run.sh` must match the one used by the goldens (`# Source:` line); a mismatch after a chart rename fails every case.

## Refactors that leave stale files

After renaming a chart or generator directory, an old copy (`build/`, `generate/`, `_computeMetadata.tpl`) can reappear untracked. Check `git status --short` for siblings with the old name before and after, diff against the new one, then delete.

## Flux / Helm adoption

- Helm 3-way merge never removes fields that are in neither the old nor the new manifest: a HelmRelease adopted from an old Kustomization can keep legacy `spec.values` keys (a `secret.additionalSecrets.<x>: {}` kept a pod in `Init` waiting for a secret). Compare `kubectl get hr -o yaml` with the golden and JSON-patch the leftovers.
- Moving a StringSecret/CNP between Helm releases gives an ownership error until the old release drops it; it self-heals on retry. An unowned pre-existing Secret is skipped by the secret generator (it keeps its values and stays orphan).
- A RWO PVC + RollingUpdate strategy deadlocks when the new pod lands on another node: scale the Deployment to 0 then 1.
- Bash used in chart scripts: `set -o pipefail` with `cmd | grep -q` fails on SIGPIPE; capture to a variable.
