{{/*
Validate datadogMetrics values
*/}}
{{- define "base.resources.datadogMetrics.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if not $object.query  -}}
    {{- fail (printf "query field is required for datadogMetrics. (alert: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}
