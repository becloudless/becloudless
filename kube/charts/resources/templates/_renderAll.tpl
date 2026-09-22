{{/*
Generic renderer for ALL resource instances of a given kind, driven by
.Values.resources.<name> (and .Values.defaults.resources.<name>).

Every value under .Values.resources.<name>.<id> and
.Values.defaults.resources.<name> is rendered through Helm's `tpl` function
(against the root context) before use, so any string field may contain Helm
template expressions (e.g. `{{ .Release.Namespace }}`, `{{ .Values.foo }}`).
This is done once on the already-merged (resource + defaults) values, after
converting them to YAML, so both the resource's own values and the kind's
defaults support templating equally. Note this means any literal `{{`/`}}`
in a value (e.g. a ConfigMap payload meant for another Go-template engine)
must be escaped (e.g. `{{"{{"}}`) or it will be interpreted as Helm syntax.
*/}}
{{- define "resources.generic.renderAll" }}
  {{- $rootContext := .rootContext }}
  {{- $name := .name }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentIsSpec := true }}
  {{- if hasKey . "contentIsSpec" }}
    {{- $contentIsSpec = .contentIsSpec }}
  {{- end }}
  {{- $required := .required | default list }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $defaultsResourcesAll := $defaultsAll.resources | default dict }}
  {{- $default := get $defaultsResourcesAll $name | default dict }}
  {{- $resourcesAll := $rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $name | default dict) }}
    {{- $merged := merge ($resource | default dict) $default }}
    {{- $merged = tpl (toYaml $merged) $rootContext | fromYaml }}

    {{- $enabled := true }}
    {{- if hasKey $merged "enabled" }}
      {{- $enabled = $merged.enabled }}
    {{- end }}

    {{- if $enabled }}
      {{- include "resources.generic.requireFields" (dict "name" $name "id" $id "resource" $merged "required" $required) }}

      {{- $metadata := include "resources.generic.computeMetadata" (dict "rootContext" $rootContext "id" $id "resource" $merged) | trim }}
      {{- $cleaned := omit $merged "nameOverride" "fullNameOverride" "namespace" "labels" "annotations" "enabled" }}
      {{- include "resources.generic.render" (dict "apiVersion" $apiVersion "kind" $kind "contentIsSpec" $contentIsSpec "metadata" $metadata "resource" $cleaned) }}
    {{- end }}
  {{- end }}
{{- end }}
