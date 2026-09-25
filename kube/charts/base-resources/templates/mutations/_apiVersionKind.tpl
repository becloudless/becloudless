{{- define "base-resources.mutations.apiVersionKind" }}
  {{- $work := .work }}
  {{- $object := $work.object | default dict }}
  {{- $object = set $object "apiVersion" .apiVersion }}
  {{- $object = set $object "kind" .kind }}
  {{- $work = set $work "object" $object }}
  {{- toYaml $work }}
{{- end }}
