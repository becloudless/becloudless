{{/*
Convert PVC values to an object
*/}}
{{- define "base.resources.persistentVolumeClaims.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- .values | toYaml -}}
{{- end -}}
