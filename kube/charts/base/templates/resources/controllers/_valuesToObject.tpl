{{/*
Convert controller values to an object
*/}}
{{- define "base.resources.controllers.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
