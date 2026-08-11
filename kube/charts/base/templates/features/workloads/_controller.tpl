{{- define "base.workloads.controller" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- $controller := dict -}}
{{- if eq $workload.type "singleton" -}}
  {{- $_ := set $controller "type" "Deployment" -}}
{{- else -}}
  {{- $_ := set $controller "type" $workload.type -}}
{{- end -}}
{{- with $workload.pod -}}
  {{- $_ := set $controller "pod" $workload.pod -}}
{{- end -}}
{{- with $workload.labels -}}
  {{- $_ := set $controller "labels" $workload.labels -}}
{{- end -}}
{{- with $workload.annotations -}}
  {{- $_ := set $controller "annotations" $workload.annotations -}}
{{- end -}}
{{- with $workload.volumes -}}
  {{- $_ := set $controller "volumes" $workload.volumes -}}
{{- end -}}
{{- with $workload.replicas -}}
  {{- $_ := set $controller "replicas" $workload.replicas -}}
{{- end -}}
{{- with $workload.strategy -}}
  {{- $_ := set $controller "strategy" $workload.strategy -}}
{{- end -}}
{{- with $workload.rollingUpdate -}}
  {{- $_ := set $controller "rollingUpdate" $workload.rollingUpdate -}}
{{- end -}}
{{- with $workload.cronJob -}}
  {{- $_ := set $controller "cronJob" $workload.cronJob -}}
{{- end -}}
{{- with $workload.job -}}
  {{- $_ := set $controller "job" $workload.job -}}
{{- end -}}
{{- with $workload.statefulSet -}}
  {{- $_ := set $controller "statefulSet" $workload.statefulSet -}}
{{- end -}}
{{- with $workload.inferenceService -}}
  {{- $_ := set $controller "inferenceService" $workload.inferenceService -}}
{{- end -}}
{{- with $workload.container -}}
  {{- $_ := set $controller "containers" (dict "main" $workload.container) -}}
{{- end -}}
{{- with $workload.initContainer -}}
  {{- $_ := set $controller "initContainers" (dict "init" $workload.initContainer) -}}
{{- end -}}


{{/* link SA to controller */}}
{{- if include "base.lib.utils.isEnabled" (dig "serviceAccount" dict $workload ) }}
  {{- $_ := merge $controller (dict "pod" (dict "serviceAccountName_resource" $workloadId)) -}}
{{- end -}}

resources:
  controllers:
    {{$workloadId}}:
      {{$controller | toYaml | nindent 6}}

{{- end -}}
