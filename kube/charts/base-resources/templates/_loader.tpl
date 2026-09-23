{{- define "base-resources.loader.all" -}}
  {{- include "base-resources.render" (dict "rootContext" $) }}
{{- end }}
