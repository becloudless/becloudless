{{/*
Validate ImageRepository values
*/}}
{{- define "base.resources.providers.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if not $object.type  -}}
    {{- fail (printf "type field is required for provider. (provider: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}
