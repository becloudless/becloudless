{{- /*
The loader of the app charts, on top of the one of the base chart (`base.loader.init`): the values of this library are the `app` key
of its values.yaml, and end up in `.Values.app` (`app.domain`, `app.name`, `app.lldapdn`), like the values of `base` end up at the
root.

Helm scopes the values of a dependency under its name, so what the library sets is `.Values.app.app`, next to what the chart or the
cluster sets with `app:`, which is seen as the root of the library (`.Values.app.domain`). They are folded together first (the
ones of the chart over the defaults of the library), then the library is merged into the values like any other.

The base chart is a dependency of the app chart too (next to this library): Flux builds the charts of this repository from git,
where the dependencies of a local dependency are not vendored (`charts/` is not committed).
*/}}
{{- /*
The values of `app.scaling` as integers. A string made of only `{{ .Values.app.scaling.<key> }}` (ex: `replicas: "{{ .Values.app.scaling.replicas }}"`)
in the resources is replaced by the value of the key, as an integer: the template engine can only give a string, which is not an integer
for the `replicas` of a Deployment (or the `replicaCount` of a public chart). It is done before the templates of the resources are
rendered, and it only applies to `.Values.app.scaling`.
*/}}
{{- define "app.loader.scalingToIntegers" }}
  {{- $scaling := ($.Values.app | default dict).scaling | default dict }}
  {{- $yaml := $.Values.resources | default dict | toYaml }}
  {{- $changed := false }}
  {{- range $marker := regexFindAll "'\\{\\{\\s*\\.Values\\.app\\.scaling\\.[A-Za-z]+\\s*\\}\\}'" $yaml -1 | uniq }}
    {{- $key := regexReplaceAll "^.*scaling\\.([A-Za-z]+).*$" $marker "${1}" }}
    {{- if not (hasKey $scaling $key) }}
      {{- fail (printf "app.scaling.%s is not a scaling value (%s)" $key (keys $scaling | sortAlpha | join ", ")) }}
    {{- end }}
    {{- $yaml = replace $marker (toString (int64 (get $scaling $key))) $yaml }}
    {{- $changed = true }}
  {{- end }}
  {{- if $changed }}
    {{- $_ := set $.Values "resources" (fromYaml $yaml) }}
  {{- end }}
{{- end }}

{{- /*
The chart of the `fluxHelmReleases` of the apps: a release that sets no `chart.spec.sourceRef` (nor a `chartRef`) is a chart of this
repository, installed from the GitRepository `bcl` of the `apps` namespace (created by the `apps` chart). Its `chart.spec` defaults to
`chart: ./kube/charts/base-loader` and `reconcileStrategy: Revision`, what it sets wins. A release with its own `sourceRef` (a
HelmRepository for example) is left as it is.
*/}}
{{- define "app.loader.helmReleasesSource" }}
  {{- $releases := ($.Values.resources | default dict).fluxHelmReleases }}
  {{- if kindIs "map" $releases }}
    {{- range $id, $release := $releases }}
      {{- if and (kindIs "map" $release) (not (hasKey $release "chartRef")) }}
        {{- $chart := $release.chart | default dict }}
        {{- $spec := $chart.spec | default dict }}
        {{- if not (hasKey $spec "sourceRef") }}
          {{- $spec = set $spec "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" "apps") }}
          {{- if not (hasKey $spec "chart") }}
            {{- $spec = set $spec "chart" "./kube/charts/base-loader" }}
          {{- end }}
          {{- if not (hasKey $spec "reconcileStrategy") }}
            {{- $spec = set $spec "reconcileStrategy" "Revision" }}
          {{- end }}
          {{- $_ := set $releases $id (set $release "chart" (set $chart "spec" $spec)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "app.loader.init" }}
  {{- $scope := $.Values.app | default dict }}
  {{- $given := omit $scope "app" "base" }}
  {{- range $key, $_ := $given }}
    {{- $_ := unset $scope $key }}
  {{- end }}
  {{- $_ := set $scope "app" (mustMergeOverwrite (deepCopy ($scope.app | default dict)) $given) }}
  {{- $_ := set $.Values "app" $scope }}

  {{- include "base.lib.init.mergeLibrariesValuesIntoValues" (dict "rootContext" $ "libraryNames" (list "app")) }}

  {{- include "app.loader.scalingToIntegers" $ }}
  {{- include "app.loader.helmReleasesSource" $ }}

  {{- include "base.loader.init" $ }}
{{- end }}

{{- define "app.loader.all" }}
  {{- include "app.loader.init" $ }}

  {{- include "base.resources.renderResources" (dict "rootContext" $) }}
{{- end }}
