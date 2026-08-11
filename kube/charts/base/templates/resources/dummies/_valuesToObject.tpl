{{/*
Convert configMap values to an object
*/}}
{{- define "base.resources.dummies.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
