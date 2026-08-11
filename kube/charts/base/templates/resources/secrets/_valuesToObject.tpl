{{/*
Convert Secret values to an object
*/}}
{{- define "base.resources.secrets.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
