
{{/*
Convert Service values to an object
*/}}
{{- define "base.resources.datadogMetrics.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
