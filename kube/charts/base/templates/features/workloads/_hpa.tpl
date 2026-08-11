{{- define "base.workloads.hpa" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- if include "base.lib.utils.isEnabled" (dig "hpa" dict $workload) }}

{{- if and (dig "hpa" "metrics" $workload) (kindIs "slice" $workload.hpa.metrics) -}}
  {{- fail (printf "hpa.metrics field must be a map of metric indexed by an identifier. (workload: %s)" $workloadId) -}}
{{- end -}}

resources:
  horizontalPodAutoscalers:
    {{$workloadId}}:
      controller: {{$workloadId}}
      {{ with $workload.hpa.minReplicas }}
      minReplicas: {{ . }}
      {{ end }}
      {{ with $workload.hpa.maxReplicas }}
      maxReplicas: {{ . }}
      {{ end }}
      {{- if $workload.hpa.behavior }}
      behavior: {{- toYaml $workload.hpa.behavior | nindent 8 }}
      {{- end }}

{{- end }}
{{- end -}}
