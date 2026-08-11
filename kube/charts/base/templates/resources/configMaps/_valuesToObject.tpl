{{/*
Convert configMap values to an object
*/}}
{{- define "base.resources.configMaps.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
