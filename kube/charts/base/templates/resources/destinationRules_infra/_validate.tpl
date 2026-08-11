{{/*
Validate PodDisruptionBudget values
*/}}
{{- define "base.resources.destinationRules.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if empty (get $object "host") -}}
    {{- fail (printf "host field is required for destinationRule. (destinationRule: %s)" $object.identifier) -}}
  {{- end -}}

{{- end -}}
