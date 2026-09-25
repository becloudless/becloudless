{{- define "base-resources.mutations.enabled" }}
  {{- $work := .work }}
  {{- $resource := $work.resource | default dict }}
  {{- $isEnabled := include "base-resources.lib.isEnabled" $resource | trim }}
  {{- $resource = omit $resource "enabled" }}
  {{- $work = set $work "resource" $resource }}
  {{- $work = set $work "enabled" (not (not $isEnabled)) }}
  {{- toYaml $work }}
{{- end }}
