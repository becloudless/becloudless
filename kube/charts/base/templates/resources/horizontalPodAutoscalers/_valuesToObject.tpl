{{/*
Convert Service values to an object
*/}}
{{- define "base.resources.horizontalPodAutoscalers.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- $rootContext := .rootContext -}}
  {{- $objectValues := .values -}}

  {{- $controller := include "base.resources.controllers.getByIdentifier" (dict "rootContext" $rootContext "id" $objectValues.controller) | fromYaml -}}
  {{- $_ := set $objectValues "controller" $controller -}}

  {{- $objectValues | toYaml -}}
{{- end -}}
