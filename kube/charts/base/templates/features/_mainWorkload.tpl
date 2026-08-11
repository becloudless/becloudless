{{- define "base.features.mainWorkload" -}}
  {{- if .Values.mainWorkload -}}
    {{- $_ := mustMergeOverwrite .Values.workloads (dict "main" .Values.mainWorkload) -}}
  {{- end -}}
{{- end -}}