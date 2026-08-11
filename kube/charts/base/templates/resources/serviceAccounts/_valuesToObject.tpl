{{/*
Convert ServiceAccount values to an object
*/}}
{{- define "base.resources.serviceAccounts.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
