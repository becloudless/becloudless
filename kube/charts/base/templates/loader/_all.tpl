{{/*
Main entrypoint for the common library chart. It will render all underlying templates based on the provided values.
*/}}
{{- define "base.loader.all" -}}
  {{- /* Generate chart and dependency values */ -}}
  {{- include "base.loader.init" . -}}

  {{- /* Generate remaining objects */ -}}
  {{- include "base.loader.generate" . -}}
{{- end -}}
