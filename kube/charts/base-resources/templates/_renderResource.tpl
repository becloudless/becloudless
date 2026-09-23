{{/*
Generic renderer for a SINGLE resource of a given kind.

Params (passed as a dict):
  apiVersion   - apiVersion of the manifest to generate (e.g. "v1")
  kind         - kind of the manifest to generate (e.g. "ConfigMap")
  contentIsSpec - boolean:
                   false -> the resource's values are merged directly at the
                            root of the manifest (e.g. ConfigMap's data/binaryData)
                   true  -> the resource's values are wrapped under a `spec:`
                            key in the manifest (e.g. HorizontalPodAutoscaler, Service)
  metadata     - the resource's pre-rendered `metadata:` YAML block (see
                 base-resources.computeMetadata)
  resource     - the resource's (already defaulted/merged) values, with the
                 well-known metadata fields (nameOverride, fullNameOverride,
                 namespace, labels, annotations) already stripped out

Renders exactly one manifest for the given metadata/resource, placing the
resource's values either at the root or under `spec:`, depending on
`contentIsSpec`.
*/}}
{{- define "base-resources.renderResource" }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentIsSpec := .contentIsSpec }}
  {{- $metadata := .metadata }}
  {{- $resource := .resource | default dict }}
---
apiVersion: {{ $apiVersion }}
kind: {{ $kind }}
{{ $metadata }}
  {{- if $contentIsSpec }}
spec:
  {{- toYaml $resource | nindent 2 }}
  {{- else }}
    {{- if $resource }}
{{- toYaml $resource | nindent 0 }}
    {{- end }}
  {{- end }}
{{- end }}
