{{- define "base-resources.mutations.required" }}
  {{- $work := .work }}
  {{- if $work.enabled }}
    {{- $name := .name }}
    {{- $id := .id }}
    {{- $resource := $work.resource | default dict }}
    {{- range $field := (.required | default list) }}
      {{- if not (hasKey $resource $field) }}
        {{- fail (printf "resources.%s.%s: %q is required" $name $id $field) }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}
