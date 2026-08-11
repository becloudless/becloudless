{{- define "base.features.debug" -}}
  {{- $rootContext := .rootContext -}}
  {{- $chartName := .chartName -}}

{{- with $rootContext.Values.debug }}
resources:
  dummies:
    debug-{{ $chartName }}:
      data:
        values: |
          {{ $rootContext.Values | toYaml | nindent 8 }}
{{- end }}
{{- end -}}
