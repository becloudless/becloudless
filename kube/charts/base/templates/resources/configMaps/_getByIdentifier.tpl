{{/*
Return a configMap Object by its Identifier.
*/}}
{{- define "base.resources.configMaps.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- $configMapValues := dig "configMaps" $identifier nil $rootContext.Values.resources -}}
  {{- if not (empty $configMapValues) -}}
    {{- include "base.resources.configMaps.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $configMapValues) -}}
  {{- end -}}
{{- end -}}
