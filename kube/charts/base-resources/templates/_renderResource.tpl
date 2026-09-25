{{- define "base-resources.renderResource" }}
  {{- $context := . }}
  {{- $work := dict "enabled" true "object" dict "resource" (.resource | default dict) }}

  {{- range $mutation := (list "base-resources.mutations.mergeDefaults" 
                               "base-resources.mutations.stringifyFields"
                               "base-resources.mutations.enabled"
                               "base-resources.mutations.required"
                               "base-resources.mutations.apiVersionKind"
                               "base-resources.mutations.metadata"
                               "base-resources.mutations.content") }}
    {{- $inputs := merge (dict "work" $work) $context }}
    {{- $work = include $mutation $inputs | fromYaml }}
  {{- end }}

{{- if $work.enabled }}
---
{{ toYaml $work.object }}
{{- end }}

{{- end }}
