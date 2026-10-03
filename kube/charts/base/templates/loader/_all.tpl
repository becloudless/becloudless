{{- define "base.loader.all" }}
  {{- include "base.loader.init" $ }}

  {{- include "base.resources.renderResources" (dict "rootContext" $) }}
{{- end }}
