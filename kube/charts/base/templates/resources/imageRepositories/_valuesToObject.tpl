{{/*
Convert ImageRepository values to an object
*/}}
{{- define "base.resources.imageRepositories.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- $rootContext := .rootContext -}}
  {{- $objectValues := .values -}}

  {{- if $objectValues.controllerContainer -}}
    {{- $controllerContainer := regexSplit "/" $objectValues.controllerContainer 2 -}}
    {{- $container := include "base.lib.container.getByIdentifier" (dict "rootContext" $rootContext "id" (last $controllerContainer) "controller" (first $controllerContainer)) | fromYaml -}}
    {{- $_ := set $objectValues "container" $container -}}
  {{- end -}}

  {{- $objectValues | toYaml -}}
{{- end -}}
