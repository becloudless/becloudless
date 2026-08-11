
{{/*
Convert Alert values to an object
*/}}
{{- define "base.resources.alerts.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
