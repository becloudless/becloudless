{{/*
Convert Service values to an object
*/}}
{{- define "base.resources.podDisruptionBudgets.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
