{{/*
Validate VirtualService values
*/}}
{{- define "base.resources.serviceEntries.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if empty (get $object "hosts") -}}
    {{- fail (printf "hosts field is required for serviceEntry. (serviceEntry: %s)" $object.identifier) -}}
  {{- end -}}
{{- end -}}
