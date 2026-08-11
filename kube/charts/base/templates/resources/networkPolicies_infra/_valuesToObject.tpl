{{/*
Convert networkPolicy values to an object
*/}}
{{- define "base.resources.networkPolicies.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
