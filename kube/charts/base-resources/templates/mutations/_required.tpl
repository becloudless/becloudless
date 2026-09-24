{{- define "base-resources.mutations.required" }}
  {{- $name := .name }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
  {{- range $field := (.required | default list) }}
    {{- if not (hasKey $resource $field) }}
      {{- fail (printf "resources.%s.%s: %q is required" $name $id $field) }}
    {{- end }}
  {{- end }}
{{- end }}
