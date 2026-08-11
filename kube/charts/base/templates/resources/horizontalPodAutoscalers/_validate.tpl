{{/*
Validate PodDisruptionBudget values
*/}}
{{- define "base.resources.horizontalPodAutoscalers.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $hpaObject := .object -}}

  {{- if empty (get $hpaObject "controller") -}}
    {{- fail (printf "controller field is required for horizontalPodAutoscaler. (hpa: %s)" $hpaObject.identifier) -}}
  {{- end -}}

  {{- if kindIs "slice" $hpaObject.metrics -}}
    {{- fail (printf "metrics field must be a map of metric indexed by an identifier. (hpa: %s)" $hpaObject.identifier) -}}
  {{- end -}}

{{- end -}}
