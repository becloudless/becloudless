{{/*
Validate ImageRepository values
*/}}
{{- define "base.resources.imageRepositories.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if not $object.container  -}}
    {{- fail (printf "controllerContainer field is required for imageRepository. (imageRepository: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}
