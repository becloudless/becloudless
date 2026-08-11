{{/*
Convert Route values to an object
*/}}
{{- define "base.resources.routes.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
