{{/*
Convert AuthorizationPolicy values to an object
*/}}
{{- define "base.resources.authorizationPolicies.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
