{{/*
Convert Service values to an object
*/}}
{{- define "base.resources.virtualServices.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
