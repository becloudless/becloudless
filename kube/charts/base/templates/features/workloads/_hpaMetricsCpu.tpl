{{- define "base.workloads.hpa.metrics.cpu" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

  {{- $metric := (dig "hpa" "metrics" "cpu" dict $workload) -}}

  {{- if and (include "base.lib.utils.isEnabled" $metric) (not $metric.averageUtilization) -}}
    {{- fail (printf "'averageUtilization' is required for hpa metric. (workload: %s,  metric: %s)" $workloadId "cpu") -}}
  {{- end -}}

{{- with $metric }}
resources:
  horizontalPodAutoscalers:
    {{$workloadId}}:
      metrics:
        cpu:
          {{- with $metric.enabled }}
          enabled: {{ . }}
          {{- end }}
          {{- with $metric.averageUtilization }}
          resource:
            name: cpu
            target:
              averageUtilization: {{$metric.averageUtilization}}
              type: Utilization
          type: Resource
          {{- end }}
{{- end }}
{{- end -}}