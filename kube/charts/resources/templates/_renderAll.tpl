{{- define "resources.generic.renderAll" }}
  {{- $rootContext := .rootContext }}
  {{- $name := .name }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentField := .contentField }}

  {{- $defaultsAll := $rootContext.Values.defaultValues | default dict }}
  {{- $default := get $defaultsAll $name | default dict }}
  {{- $resourcesAll := $rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $name | default dict) }}
    {{- $merged := merge ($resource | default dict) $default }}
    {{- include "resources.generic.render" (dict "apiVersion" $apiVersion "kind" $kind "contentField" $contentField "id" $id "resource" $merged) }}
  {{- end }}
{{- end }}
