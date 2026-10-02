{{- define "base.renderResource" }}
  {{- $context := . }}
  {{- $work := dict "enabled" true "object" dict "resource" (.resource | default dict) }}

  {{- range $mutation := (list "base.mutations.defaults" 
                               "base.mutations.stringifyFields"
                               "base.mutations.enabled"
                               "base.mutations.required"
                               "base.mutations.apiVersionKind"
                               "base.mutations.metadata"
                               "base.mutations.mapsToArrays"
                               "base.mutations.content") }}
    {{- $inputs := merge (dict "work" $work) $context }}
    {{- $work = include $mutation $inputs | fromYaml }}
  {{- end }}

{{- if $work.enabled }}
---
{{ toYaml $work.object }}
{{- end }}

{{- end }}
