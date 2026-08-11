{{- define "base.workloads.hpa.metrics.rabbitmqReadyMessagesCount" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

  {{- $metric := (dig "hpa" "metrics" "rabbitmqReadyMessagesCount" dict $workload) -}}

{{- if include "base.lib.utils.isEnabled" $metric }}

  {{- if not $metric.queueName -}}
    {{- fail (printf "queueName is mandatory for HPA metric. (workload: %s, metric: %s)" $workloadId "rabbitmqReadyMessagesCount") -}}
  {{- end -}}

  {{- $query := printf "avg:rabbitmq.queue.messages_ready{env:%s,rabbitmq_vhost:%s,rabbitmq_queue:%s}.rollup(5)"
                 $rootContext.environment
                 (default "*" $metric.vhost)
                 $metric.queueName -}}

resources:
  horizontalPodAutoscalers:
    {{$workloadId}}:
      metrics:
        rabbitmqReadyMessagesCount:
          {{- include "base.workloads.hpa.metrics.datadogQuery.builder" (dict "rootContext" $rootContext
                                                                                        "workloadId" $workloadId
                                                                                        "metricIdentifier" "rabbitmqreadymessagescount"
                                                                                        "datadogQuery" (dict "query" $query "value" (default 5 $metric.target))) | nindent 10 }}
  datadogMetrics:
    {{$workloadId}}-rabbitmqreadymessagescount:
      nameOverride: "{{ include "base.lib.resource.resourceNameOverride" (dict "workloadId" $workloadId "resourceSuffix" "rabbitmqreadymessagescount") }}"
      query: "{{ $query }}"
{{- end }}
{{- end -}}
