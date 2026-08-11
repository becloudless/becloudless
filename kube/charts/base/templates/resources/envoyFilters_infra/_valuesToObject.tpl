{{/*
Convert EnvoyFilter values to an object
*/}}
{{- define "base.resources.envoyFilters.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
