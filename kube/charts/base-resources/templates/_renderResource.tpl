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
