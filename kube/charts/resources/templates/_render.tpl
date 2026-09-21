{{/*
Generic renderer for a SINGLE resource of a given kind.

Params (passed as a dict):
  apiVersion   - apiVersion of the manifest to generate (e.g. "v1")
  kind         - kind of the manifest to generate (e.g. "ConfigMap")
  contentField - boolean:
                   true  -> the resource's values are merged directly at the
                            root of the manifest (e.g. ConfigMap's data/binaryData)
                   false -> the resource's values are wrapped under a `spec:`
                            key in the manifest (e.g. HorizontalPodAutoscaler, Service)
  name         - the resource's final metadata.name (see resources.generic.computeName)
  resource     - the resource's (already defaulted/merged) values

Renders exactly one manifest for the given name/resource, placing its values
either at the root or under `spec:`, depending on `contentField`.
*/}}
{{- define "resources.generic.render" }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentFromRoot := .contentField }}
  {{- $name := .name }}
  {{- $resource := .resource | default dict }}
---
apiVersion: {{ $apiVersion }}
kind: {{ $kind }}
metadata:
  name: {{ $name }}
  {{- if $contentFromRoot }}
    {{- if $resource }}
{{- toYaml $resource | nindent 0 }}
    {{- end }}
  {{- else }}
spec:
  {{- toYaml $resource | nindent 2 }}
  {{- end }}
{{- end }}
