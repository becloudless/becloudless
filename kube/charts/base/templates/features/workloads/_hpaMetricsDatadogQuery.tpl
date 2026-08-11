{{- define "base.workloads.hpa.metrics.datadogQuery" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

  {{- $metric := (dig "hpa" "metrics" "datadogQuery" dict $workload) -}}

{{- if include "base.lib.utils.isEnabled" $metric }}
resources:
  horizontalPodAutoscalers:
    {{$workloadId}}:
      metrics:
        datadogQuery:
          {{- include "base.workloads.hpa.metrics.datadogQuery.builder" (dict "rootContext" $rootContext
                                                                                        "workloadId" $workloadId
                                                                                        "metricIdentifier" "datadogQuery"
                                                                                        "datadogQuery" $metric) | nindent 10 }}
  datadogMetrics:
    {{$workloadId}}-datadogquery:
      nameOverride: "{{ include "base.lib.resource.resourceNameOverride" (dict "workloadId" $workloadId "resourceSuffix" "datadogquery") }}"
      query: {{tpl $workload.hpa.metrics.datadogQuery.query $rootContext}}
{{- end }}
{{- end -}}



{{- define "base.workloads.hpa.metrics.datadogQuery.builder" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $metricIdentifier := .metricIdentifier -}}
  {{- $datadogQuery := .datadogQuery -}}

  {{- if include "base.lib.utils.isEnabled" $datadogQuery -}}
    {{- if not $datadogQuery.query -}}
      {{- fail (printf "'query' is required for hpa metric. (workload: %s,  metric: %s)" $workloadId $metricIdentifier) -}}
    {{- end -}}

    {{- if and (not $datadogQuery.averageValue) (not $datadogQuery.value) -}}
      {{- fail (printf "'averageValue' or 'value' is required for hpa metric. (workload: %s,  metric: %s)" $workloadId $metricIdentifier) -}}
    {{- end -}}

    {{- if and $datadogQuery.averageValue $datadogQuery.value -}}
      {{- fail (printf "'averageValue' or 'value' are mutually exclusive for hpa metric. (workload: %s,  metric: %s)" $workloadId $metricIdentifier) -}}
    {{- end -}}

  {{- end -}}


{{- with not (include "base.lib.utils.isEnabled" $datadogQuery) }}
enabled: false
{{- else }}
type: External
external:
  metric:
    name: datadogmetric@{{$rootContext.Release.Namespace}}:{{ include "base.lib.resource.workloadFullname" (dict "rootContext" $rootContext "workloadId" $workloadId) }}-{{ $metricIdentifier | lower }}
  target:
    {{- if $datadogQuery.averageValue }}
    type: AverageValue
    averageValue: {{$datadogQuery.averageValue}}
    {{- else }}
    type: Value
    value: {{$datadogQuery.value}}
    {{- end }}
{{- end }}
{{- end -}}
