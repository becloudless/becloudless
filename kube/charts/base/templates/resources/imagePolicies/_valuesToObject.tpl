{{/*
Convert ImagePolicy values to an object
*/}}
{{- define "base.resources.imagePolicies.valuesToObject" -}}
  {{- include "base.lib.resource.defaultValuesToObject" . -}}
  {{- $rootContext := .rootContext -}}
  {{- $objectValues := .values -}}

  {{- $imageRepository := include "base.resources.imageRepositories.getByIdentifier" (dict "rootContext" $rootContext "id" $objectValues.imageRepository) | fromYaml -}}
  {{- $_ := set $objectValues "imageRepository" $imageRepository -}}

  {{- $objectValues | toYaml -}}
{{- end -}}
