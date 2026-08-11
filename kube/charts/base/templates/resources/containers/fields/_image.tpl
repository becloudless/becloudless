{{/*
Image used by the container.
*/}}
{{- define "base.resources.containers.fields.image" -}}
  {{- $ctx := .ctx -}}
  {{- $rootContext := $ctx.rootContext -}}
  {{- $containerObject := $ctx.containerObject -}}

  {{- $imageRepo := $containerObject.image.repository -}}
  {{- $imageTag := $containerObject.image.tag -}}

  {{- if and $imageRepo $imageTag -}}
    {{- printf "%s:%s" $imageRepo $imageTag -}}
  {{- end -}}
{{- end -}}
