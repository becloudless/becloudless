{{/*
Validate StatefulSet values
*/}}
{{- define "base.resources.statefulSets.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $statefulSetValues := .object -}}

  {{- if and (ne $statefulSetValues.strategy "OnDelete") (ne $statefulSetValues.strategy "RollingUpdate") -}}
    {{- fail (printf "Not a valid strategy type for StatefulSet. (controller: %s, strategy: %s)" $statefulSetValues.identifier $statefulSetValues.strategy) -}}
  {{- end -}}

  {{- if not (empty (dig "statefulSet" "volumeClaimTemplates" "" $statefulSetValues)) -}}
    {{- range $index, $volumeClaimTemplate := $statefulSetValues.statefulSet.volumeClaimTemplates -}}
      {{- if empty (get . "size") -}}
        {{- fail (printf "size is required for volumeClaimTemplate. (controller: %s, volumeClaimTemplate: %s)" $statefulSetValues.identifier $volumeClaimTemplate.name) -}}
      {{- end -}}

      {{- if empty (get . "accessMode") -}}
        {{- fail (printf "accessMode is required for volumeClaimTemplate. (controller: %s, volumeClaimTemplate: %s)" $statefulSetValues.identifier $volumeClaimTemplate.name) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
