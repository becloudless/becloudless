{{/*
Validate PodDisruptionBudget values
*/}}
{{- define "base.resources.podDisruptionBudgets.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $pdbObject := .object -}}

  {{- if empty (get $pdbObject "controller") -}}
    {{- fail (printf "controller field is required for PodDisruptionBudget. (pdb: %s)" $pdbObject.identifier) -}}
  {{- end -}}

{{- end -}}
