{{- define "base-resources.mutations.apiVersionKind" }}
  {{- $object := .object | default dict }}
  {{- $object = set $object "apiVersion" .apiVersion }}
  {{- $object = set $object "kind" .kind }}
  {{- toYaml $object }}
{{- end }}
