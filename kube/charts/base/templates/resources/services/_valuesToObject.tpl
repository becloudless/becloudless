{{/*
Convert Service values to an object
*/}}
{{- define "base.resources.services.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
