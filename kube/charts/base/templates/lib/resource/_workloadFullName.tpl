{{/*
compute the workload fullname based on the workloadId
*/}}
{{- define "base.lib.resource.workloadFullname" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}

  {{- $fullname := printf "%s-%s" $rootContext.Release.Name $workloadId -}}
  {{- if eq $workloadId "main" -}}
     {{- $fullname = $rootContext.Release.Name -}}
  {{- end -}}
  {{- $fullname -}}
{{- end -}}
