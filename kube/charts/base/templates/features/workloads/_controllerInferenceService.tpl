{{- define "base.workloads.controllerInferenceService" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- if eq $workload.type "InferenceService" }}
{{- /* InferenceService have some own mechanism for hpa and services */}}
workloads:
  {{$workloadId}}:
    hpa:
      enabled: false
    service:
      enabled: false
{{- end -}}


{{- end -}}
