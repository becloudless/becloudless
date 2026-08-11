{{- define "base.features.workloads" -}}
  {{- $rootContext := .rootContext -}}
  {{- range $workloadId, $workload := $rootContext.Values.workloads  -}}
    {{- if include "base.lib.utils.isEnabled" (get $rootContext.Values.workloads $workloadId) -}}
      {{/* merge workloads default into current workload */}}
      {{- include "base.lib.utils.explicitlyEnableWhenDefaultValuesAreDisabled" (dict "default" $rootContext.Values.chartDefaults.workload "current" $workload) -}}
      {{- $workload = mergeOverwrite (deepCopy $rootContext.Values.chartDefaults.workload) $workload -}}
      {{/* put the prepared workloads values, including defaults, in .Values so downstream charts will see a prepared workload */}}
      {{- $_ := set $rootContext.Values.workloads $workloadId $workload -}}

      {{- /* order matters since features could depend on others */}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.controller" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{/* `inferenceService` must be run before `resources` to disable HPA and Service*/}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.controllerInferenceService" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.controllerCronJob" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.controllerSingleton" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.resources" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.hpa" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.hpa.metrics.cpu" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.hpa.metrics.customs" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.hpa.metrics.datadogQuery" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.hpa.metrics.rabbitmqReadyMessagesCount" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.scheduling" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.istio" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.istioResources" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.istioPubliclyExposed" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.istioPrivatelyExposed" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.flux" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.datadog" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
      {{- include "base.lib.utils.mergeOverwriteValues" (dict "rootContext" $rootContext "obj" (include "base.workloads.kafka" (dict "rootContext" $rootContext "workloadId" $workloadId "workload" $workload) | fromYaml)) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
