{{- define "base.workloads.flux" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- if include "base.lib.utils.isEnabled" (dig "flux" "imageAutomation" dict $workload ) -}}
resources:
  imagePolicies:
    {{$workloadId}}:
      imageRepository: main
  imageRepositories:
    {{$workloadId}}:
      controllerContainer: main/main

{{- end -}}
{{- end }}
