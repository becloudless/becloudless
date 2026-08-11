{{/*
Convert requestAuthentication values to an object
*/}}
{{- define "base.resources.requestAuthentications.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
