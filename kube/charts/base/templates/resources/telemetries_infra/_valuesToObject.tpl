{{/*
Convert Telemetry values to an object
*/}}
{{- define "base.resources.telemetries.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
