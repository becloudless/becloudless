{{- define "resources.loader.all" -}}
  {{- include "resources.render" (dict "rootContext" $) }}
{{- end }}
