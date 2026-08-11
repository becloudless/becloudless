{{- define "base.workloads.controllerCronJob" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- if or (eq $workload.type "CronJob") (eq $workload.type "Job") }}
{{- /* A Job/CronJob is not supposed to be part of a service nor scale up/down nor being rolled-out. */}}
workloads:
  {{$workloadId}}:
    hpa:
      enabled: false
    pdb:
      enabled: false
    service:
      enabled: false
    datadog:
      dogstatsd:
        enabled: true
      checks:
        openmetrics:
          enabled: false
{{- end -}}


{{- end -}}
