{{- define "base.workloads.hpa.metrics.customs" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

  {{- $metric := (dig "hpa" "metrics" "customs" dict $workload) -}}

{{- with $metric }}
resources:
  horizontalPodAutoscalers:
    {{$workloadId}}:
      metrics:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- end -}}