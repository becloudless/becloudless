{{/*
Convert Secret values to an object
*/}}
{{- define "base.resources.sealedSecrets.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
