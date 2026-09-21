{{- define "resources.generic.render" }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentFromRoot := .contentField }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
---
apiVersion: {{ $apiVersion }}
kind: {{ $kind }}
metadata:
  name: {{ $id }}
  {{- if $contentFromRoot }}
    {{- if $resource }}
{{- toYaml $resource | nindent 0 }}
    {{- end }}
  {{- else }}
spec:
  {{- toYaml $resource | nindent 2 }}
  {{- end }}
{{- end }}
