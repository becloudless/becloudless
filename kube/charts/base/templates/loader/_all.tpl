{{- define "base.loader.all" }}
  {{- include "base.loader.init" $ }}

  {{- include "base.render" (dict "rootContext" $) }}
{{- end }}
