{{/*
Convert ingress values to an object
*/}}
{{- define "base.resources.ingresses.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
