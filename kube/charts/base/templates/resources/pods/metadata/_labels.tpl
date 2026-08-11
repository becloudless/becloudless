{{- /*
Returns the value for labels
*/ -}}
{{- define "base.resources.pods.metadata.labels" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerObject := .controllerObject -}}

  {{- /* Default labels */ -}}
  {{- $labels := merge
    (dict "app.kubernetes.io/component" $controllerObject.identifier)
    (include "base.lib.metadata.globalLabels" $rootContext | fromYaml)
  -}}

  {{- /* Fetch the Pod selectorLabels */ -}}
  {{- $selectorLabels := include "base.lib.metadata.selectorLabels" $rootContext | fromYaml -}}
  {{- if not (empty $selectorLabels) -}}
    {{- $labels = merge $selectorLabels $labels -}}
  {{- end -}}

  {{- /* See if a pod-specific override is set */ -}}
  {{- if hasKey $controllerObject "pod" -}}
    {{- $podOption := get $controllerObject.pod "labels" -}}
    {{- if not (empty $podOption) -}}
      {{- $labels = merge $podOption $labels -}}
    {{- end -}}
  {{- end -}}

  {{- if not (empty $labels) -}}
    {{- $labels | toYaml -}}
  {{- end -}}
{{- end -}}
