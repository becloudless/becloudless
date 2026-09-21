{{/*
Generic renderer for a single resource kind (ConfigMap, Secret, ...).

Params (passed as a dict):
  rootContext   - the root Helm context (usually `$`)
  name          - key under .Values.resources / .Values.defaultValues (e.g. "configMaps")
  apiVersion    - apiVersion of the manifest to generate (e.g. "v1")
  kind          - kind of the manifest to generate (e.g. "ConfigMap")
  contentFields - list of field names holding the resource's content (e.g. (list "data" "binaryData"))

For every entry under `.Values.resources.<name>`, merges `.Values.defaultValues.<name>`
as defaults, then renders one manifest of the given apiVersion/kind, using the entry's
key as the resource name and each entry of `contentFields` as a payload field.
*/}}
{{- define "resources.generic.render" }}
  {{- $rootContext := .rootContext }}
  {{- $name := .name }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentFields := .contentFields }}

  {{- $defaultsAll := $rootContext.Values.defaultValues | default dict }}
  {{- $default := get $defaultsAll $name | default dict }}
  {{- $resourcesAll := $rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $name | default dict) }}
    {{- $merged := merge ($resource | default dict) $default }}
---
apiVersion: {{ $apiVersion }}
kind: {{ $kind }}
metadata:
  name: {{ $id }}
    {{- range $contentFields }}
{{ . }}:
  {{- toYaml (get $merged . | default dict) | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end }}
