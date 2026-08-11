{{/* Selector labels shared across objects */}}
{{- define "base.lib.metadata.selectorLabels" -}}
app.kubernetes.io/name: {{ include "base.lib.chart.names.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
