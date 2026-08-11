
{{- define "base.workloads.datadog" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- if include "base.lib.utils.isEnabled" (dig "datadog" dict $workload ) -}}
{{- $datadog := $workload.datadog -}}
{{- $service := include "base.workloads.datadog.serviceName" (dict "rootContext" $rootContext
                                                                   "workloadId" $workloadId
                                                                   "workload" $workload) -}}
{{- $controller := index $rootContext.Values.resources.controllers $workloadId -}}

{{- if include "base.lib.utils.isEnabled" $datadog.unifiedTagging }}
  {{- if not (dig "containers" "main" "image" "tag" nil $controller) }}
    {{- fail (printf "datadog unified tagging requires controller main container image tag to be set (controller: %s)" $workloadId) -}}
  {{- end }}
  {{- if eq $workloadId "main" }}
global:
  labels:
    tags.datadoghq.com/service: {{ $service | lower | quote }}
    tags.datadoghq.com/version: {{ tpl (toString $controller.containers.main.image.tag) $rootContext | quote }}
  {{- end }}
{{- end }}

resources:
  {{- include "base.workloads.datadog.labelResource" (dict "rootContext" $rootContext "workloadId" $workloadId "controller" $controller "service" $service "datadog" $datadog "resourcesName" "services") | nindent 2 }}
  {{- include "base.workloads.datadog.labelResource" (dict "rootContext" $rootContext "workloadId" $workloadId "controller" $controller "service" $service "datadog" $datadog "resourcesName" "horizontalPodAutoscalers") | nindent 2 }}
  {{- include "base.workloads.datadog.labelResource" (dict "rootContext" $rootContext "workloadId" $workloadId "controller" $controller "service" $service "datadog" $datadog "resourcesName" "podDisruptionBudgets") | nindent 2 }}
  {{- include "base.workloads.datadog.labelResource" (dict "rootContext" $rootContext "workloadId" $workloadId "controller" $controller "service" $service "datadog" $datadog "resourcesName" "serviceAccounts") | nindent 2 }}

  controllers:
    {{$workloadId}}:

      {{- if include "base.lib.utils.isEnabled" $datadog.unifiedTagging }}
      labels:
        tags.datadoghq.com/service: {{ $service | lower | quote }}
        tags.datadoghq.com/version: {{ tpl (toString $controller.containers.main.image.tag) $rootContext | quote }}
      {{- end }}

      {{- if include "base.lib.utils.isEnabled" $datadog.unixSocket }}
      volumes:
        dsdsocket:
          type: hostPath
          hostPath: /var/run/datadog
          containers:
            main:
              path: /var/run/datadog
      {{- end }}

      pod:
        labels:
          tags.datadoghq.com/service: {{ $service | lower | quote }}
          tags.datadoghq.com/version: {{ tpl (toString $controller.containers.main.image.tag) $rootContext | quote }}

        {{- if or (include "base.lib.utils.isEnabled" $datadog.logConfig) (include "base.lib.utils.isEnabled" $datadog.checks) }}
        annotations:
          {{- if include "base.lib.utils.isEnabled" $datadog.logConfig }}
          ad.datadoghq.com/main.logs: '[{"source": "{{ $datadog.logConfig.source }}", "service": "{{ $service }}"}]'
          {{- end }}
          {{- if include "base.lib.utils.isEnabled" $datadog.checks }}
          ad.datadoghq.com/main.checks: |
            {
              "openmetrics": {
                "init_config": {},
                "instances": [
              {{- $array := list }}
              {{- if include "base.lib.utils.isEnabled" $datadog.checks.openmetrics }}
                {{- $servicePort := (dig "resources" "services" $workloadId "ports" "http" "port" nil $rootContext.Values) }}
                {{- range $instanceName, $instance := $datadog.checks.openmetrics.instances }}
                  {{- $port := default $servicePort $instance.port }}
                  {{- if not $port -}}
                    {{ fail (printf "datadog openmetrics should have a http port. Please set a port attribute for your openmetrics instance (`datadog.checks.openmetrics.instances[].port`) or define a default port for your Kube service (`resources.services.%s.ports.http.port`)" $workloadId) }}
                  {{- end -}}
                  {{- $array = append $array  (include "base.workloads.datadog.openmetrics" (dict "rootContext" $rootContext "value" $instance "port" $port "defaultPath" $datadog.checks.openmetrics.path "defaultCollectCountersWithDistributions" $datadog.checks.openmetrics.collect_counters_with_distributions "defaultMaxReturnedMetrics" $datadog.checks.openmetrics.max_returned_metrics)) }}
                {{- end }}
              {{- end }}
{{ $array | join "," | indent 18 }}
                ]
              }
            }
          {{- end }}
        {{- end }}

      containers:
        main:
          env:
            {{- if or (and (include "base.lib.utils.isEnabled" $datadog.tracerAgent) (include "base.lib.utils.isEnabled" $datadog.tracerAgent.tracing) (not (include "base.lib.utils.isEnabled" $datadog.unixSocket))) (and (include "base.lib.utils.isEnabled" $datadog.dogstatsd) (not (include "base.lib.utils.isEnabled" $datadog.unixSocket))) }}
            # DD_AGENT_HOST is to send metrics threw udp & traces if no unix socket
            DD_AGENT_HOST:
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            {{- end }}

            {{- if include "base.lib.utils.isEnabled" $datadog.unifiedTagging }}
            DD_SERVICE:
              valueFrom:
                fieldRef:
                    fieldPath: metadata.labels['tags.datadoghq.com/service']
            DD_VERSION:
              valueFrom:
                fieldRef:
                    fieldPath: metadata.labels['tags.datadoghq.com/version']
            {{- end }}

            {{- if include "base.lib.utils.isEnabled" $datadog.tracerAgent }}
            DD_PROFILING_ENABLED: {{ $datadog.tracerAgent.profiling.enabled | quote }}
            {{- end }}
            # explicitly set the value, even though DD_TRACE_ENABLED defaults to "true"
            DD_TRACE_ENABLED: "{{- if (include "base.lib.utils.isEnabled" $datadog.tracerAgent.tracing) }}true{{ else }}false{{- end }}"

            {{- if and (include "base.lib.utils.isEnabled" $datadog.tracerAgent) (include "base.lib.utils.isEnabled" $datadog.tracerAgent.tracing)}}
            #no logs injection for node js so we put this var by default when enabling tracing
            DD_LOGS_INJECTION:  {{ $datadog.tracerAgent.logsInjection.enabled | quote }}
            {{- if include "base.lib.utils.isEnabled" $datadog.tracerAgent.tracing.serviceMapping }}
            DD_SERVICE_MAPPING:
            {{- $mappings := list }}
            {{- range $datadog.tracerAgent.tracing.serviceMapping.mappedServices }}
            {{- $mappings = append $mappings (printf "%s:%s-%s" . $service .) }}
            {{- end }}
              value: {{ join "," $mappings | quote }}
            {{- end }}
            ##DD_TRACE_AGENT_URL take precedence over
            {{- if include "base.lib.utils.isEnabled" $datadog.unixSocket }}
            DD_TRACE_AGENT_URL:
              value: "unix:///var/run/datadog/apm.socket"
            {{- end }}

            DD_TRACE_SAMPLE_RATE: {{ $datadog.tracerAgent.tracing.sampleRate | quote }}
            {{- if and (include "base.lib.utils.isEnabled" $datadog.tracerAgent.jmx) (include "base.lib.utils.isEnabled" $datadog.tracerAgent.jmx.tomcat) }}
            DD_JMXFETCH_TOMCAT_ENABLED: "true"
            {{- end }}
            {{- if and (include "base.lib.utils.isEnabled" $datadog.tracerAgent.jmx) (include "base.lib.utils.isEnabled" $datadog.unixSocket)  }}
            DD_JMXFETCH_STATSD_HOST: "unix:///var/run/datadog/dsd.socket"
            DD_JMXFETCH_STATSD_PORT: "0"
            {{- end }}
            # explicitly set the value, even though DD_JMXFETCH_ENABLED defaults to "true"
            DD_JMXFETCH_ENABLED: "{{- if (include "base.lib.utils.isEnabled" $datadog.tracerAgent.jmx) }}true{{ else }}false{{- end }}"
            {{- if include "base.lib.utils.isEnabled" $datadog.tracerAgent.tagQuery }}
            DD_HTTP_CLIENT_TAG_QUERY_STRING: "true"
            DD_HTTP_SERVER_TAG_QUERY_STRING: "true"
            {{- $tagQuery := list "x-correlation-id" "x-visitor-id" "x-passenger-uuid" "x-locale" "x-client" "x-currency" }}
            {{- $tagQuery := concat $tagQuery $datadog.tracerAgent.tagQuery.custom | uniq }}
            DD_TRACE_REQUEST_HEADER_TAGS: {{ join "," $tagQuery | quote }}
            DD_TRACE_RESPONSE_HEADER_TAGS: {{ join "," $tagQuery | quote }}
            {{- end }}
            {{- end }}


            {{- if include "base.lib.utils.isEnabled" $datadog.dogstatsd }}
            {{- if not (include "base.lib.utils.isEnabled" $datadog.unixSocket) }}
            # DD_ENTITY_ID is to add pod name when using UDP
            DD_ENTITY_ID:
              valueFrom:
                fieldRef:
                  fieldPath: metadata.uid
            {{- end }}
            # if $datadog.unixSocket.enabled see volumes volumeMounts
            {{- end }}
{{- end -}}
{{- end }}

{{- define "base.workloads.datadog.labelResource" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $controller := .controller -}}
  {{- $resourcesName := .resourcesName -}}
  {{- $service := .service -}}
  {{- $datadog := .datadog -}}

{{- if include "base.lib.utils.isEnabled" $datadog.unifiedTagging }}
{{- if include "base.lib.utils.isEnabled" (dig $resourcesName $workloadId dict $rootContext.Values.resources) }}
{{$resourcesName}}:
  {{$workloadId}}:
    labels:
      tags.datadoghq.com/service: {{ $service | lower | quote }}
      tags.datadoghq.com/version: {{ tpl (toString $controller.containers.main.image.tag) $rootContext | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/* This can be used in other features and downstream chart to compute the datadog service name */}}
{{- define "base.workloads.datadog.serviceName" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

  {{ default (include "base.lib.resource.workloadFullname" (dict "rootContext" $rootContext "workloadId" $workloadId)) $workload.datadog.unifiedTagging.service }}
{{- end -}}


{{- define "base.workloads.datadog.openmetrics" -}}
  {{- $rootContext := .rootContext -}}
  {{- $value := .value -}}
  {{- $port := .port -}}
  {{- $defaultPath := .defaultPath -}}
  {{- $defaultCollectCountersWithDistributions := .defaultCollectCountersWithDistributions -}}
  {{- $defaultMaxReturnedMetrics := .defaultMaxReturnedMetrics -}}
{
  "openmetrics_endpoint": "http://%%host%%:{{ default $port }}{{ default $defaultPath $value.path }}",
  {{/* We allow the namespace to be templatized, to support things like ".Release.Namespace" */ -}}
  "namespace": {{ tpl (default "" $value.namespace) $rootContext | quote }},
  {{- $metrics := list -}}
  {{- range $current := $value.metrics }}
    {{- /* We allow the metric to be templatized, to support things like ".Release.Name" */ -}}
    {{- $tplMetric := tpl $current $rootContext -}}
    {{- $metrics = append $metrics ($tplMetric | lower | replace "-" "_" | quote) -}}
  {{- end }}
  "metrics": [
    {{ join "," $metrics }}
  ],
  "collect_counters_with_distributions": {{ $defaultCollectCountersWithDistributions }},
  "max_returned_metrics": {{ default $defaultMaxReturnedMetrics $value.max_returned_metrics }}
}
{{- end }}
