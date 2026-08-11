{{/*
This function compute the nameOverride of a resources related to a workload, based on the workloadId, possible related resource and the suffix we want to apply
*/}}
{{- define "base.lib.resource.resourceNameOverride" -}}
  {{- $workloadId := .workloadId -}}
  {{- $resourceSuffix := .resourceSuffix -}}
  {{- $relatedResourceNameOverride := .relatedResourceNameOverride -}}

  {{- if $relatedResourceNameOverride -}}
    {{- $workloadId = $relatedResourceNameOverride -}}
  {{- end -}}
  {{- $nameOverride := printf "%s-%s" $workloadId $resourceSuffix -}}
  {{- if and (eq $workloadId "main") (eq $resourceSuffix "main") }}
    {{- $nameOverride = "-" -}}
  {{- else if eq $workloadId "main" -}}
    {{- $nameOverride = $resourceSuffix -}}
  {{- else if eq $resourceSuffix "main" -}}
    {{- $nameOverride = $workloadId -}}
  {{- end -}}
  {{- $nameOverride -}}
{{- end -}}