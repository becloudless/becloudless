{{/* Expand the name of the chart */}}
{{- define "base.lib.chart.names.name" -}}
  {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "base.lib.chart.names.fullname" -}}
  {{- include "base.lib.chart.names.name" . -}}
{{- end -}}

{{/* Create chart name and version as used by the chart label */}}
{{- define "base.lib.chart.names.chart" -}}
  {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
