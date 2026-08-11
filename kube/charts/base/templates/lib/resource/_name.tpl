{{/* Compute resource name based on resource attributes and chart fullname */}}
{{- define "base.lib.resource.name" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- $objectName := "" -}}
  {{- if eq $identifier "main" -}}
    {{- $objectName = include "base.lib.chart.names.fullname" $rootContext -}}
  {{- else -}}
    {{- $objectName = printf "%s-%s" (include "base.lib.chart.names.fullname" $rootContext) $identifier -}}
  {{- end -}}

  {{- if $objectValues.nameOverride -}}
    {{- if eq $objectValues.nameOverride "-" -}}
      {{- $objectName = include "base.lib.chart.names.fullname" $rootContext -}}
    {{- else -}}
      {{- $objectName = printf "%s-%s" (include "base.lib.chart.names.fullname" $rootContext) $objectValues.nameOverride -}}
    {{- end -}}
  {{- end -}}

  {{- $objectName -}}
{{- end -}}
