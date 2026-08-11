{{/*
resourceId compute the resourceId based on the workload and the resource name
usually id is {{$workloadId}}-{{$resourceName}}}
but if both are main, then it can be the workloadId only
*/}}
{{- define "base.lib.resource.resourceId" -}}
  {{- $workloadId := .workloadId -}}
  {{- $resourceName := .resourceName -}}

  {{- $resourceId := printf "%s-%s" $workloadId $resourceName -}}
  {{- if not $resourceName -}}
    {{- $resourceId = $workloadId -}}
  {{- end -}}
  {{- if and (eq $workloadId "main") (eq $resourceName "main")  }}
    {{- $resourceId = $workloadId -}}
  {{- end -}}
  {{- $resourceId -}}
{{- end -}}
