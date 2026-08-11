{{- define "base.workloads.controllerSingleton" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- if eq $workload.type "singleton" }}
workloads:
  {{$workloadId}}:
    hpa:
      enabled: false
    pdb:
      enabled: false
    replicas: 1
    strategy: Recreate
{{- end -}}
{{- end -}}
