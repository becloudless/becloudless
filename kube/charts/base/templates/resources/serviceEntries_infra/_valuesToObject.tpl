{{/*
Convert Service values to an object
*/}}
{{- define "base.resources.serviceEntries.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
