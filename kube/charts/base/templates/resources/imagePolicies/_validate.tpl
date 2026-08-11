{{/*
Validate ImagePolicy values
*/}}
{{- define "base.resources.imagePolicies.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if not $object.imageRepository  -}}
    {{- fail (printf "imageRepository is required for imagePolicy. (imagePolicy: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}
