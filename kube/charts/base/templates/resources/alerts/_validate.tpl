{{/*
Validate Alert values
*/}}
{{- define "base.resources.alerts.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if not $object.provider  -}}
    {{- fail (printf "provider field is required for alert. (alert: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}