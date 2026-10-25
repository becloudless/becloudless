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
{{- define "app.loader.init" }}
  {{- $scope := $.Values.app | default dict }}
  {{- $given := omit $scope "app" "base" }}
  {{- range $key, $_ := $given }}
    {{- $_ := unset $scope $key }}
  {{- end }}
  {{- $_ := set $scope "app" (mustMergeOverwrite (deepCopy ($scope.app | default dict)) $given) }}
  {{- $_ := set $.Values "app" $scope }}

  {{- include "base.lib.init.mergeLibrariesValuesIntoValues" (dict "rootContext" $ "libraryNames" (list "app")) }}

  {{- include "base.loader.init" $ }}
{{- end }}

{{- define "app.loader.all" }}
  {{- include "app.loader.init" $ }}

  {{- include "base.resources.renderResources" (dict "rootContext" $) }}
{{- end }}
