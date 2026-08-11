{{/* Common labels shared across objects */}}
{{- define "base.lib.metadata.allLabels" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .identifier -}}
helm.sh/chart: {{ include "base.lib.chart.names.chart" $rootContext }}
{{ include "base.lib.metadata.selectorLabels" $rootContext }}
  {{- if $rootContext.Chart.AppVersion }}
app.kubernetes.io/version: {{ $rootContext.Chart.AppVersion | quote }}
  {{- end }}
app.kubernetes.io/managed-by: {{ $rootContext.Release.Service }}
  {{- if $identifier }}
app.kubernetes.io/component: {{ regexFind "[a-zA-Z0-9]*" $identifier }}
  {{- end }}
{{ include "base.lib.metadata.globalLabels" $rootContext }}
{{- end -}}
