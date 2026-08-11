{{/*
Validate VirtualService values
*/}}
{{- define "base.resources.virtualServices.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if empty (get $object "hosts") -}}
    {{- fail (printf "hosts field is required for virtualService. (virtualService: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}
