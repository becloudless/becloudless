{{- define "resources.generic.renderAll" }}
  {{- $rootContext := .rootContext }}
  {{- $name := .name }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentIsSpec := true }}
  {{- if hasKey . "contentIsSpec" }}
    {{- $contentIsSpec = .contentIsSpec }}
  {{- end }}

  {{- $defaultsAll := $rootContext.Values.defaultValues | default dict }}
  {{- $default := get $defaultsAll $name | default dict }}
  {{- $resourcesAll := $rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $name | default dict) }}
    {{- $merged := merge ($resource | default dict) $default }}

    {{- $fullName := include "resources.generic.computeName" (dict "rootContext" $rootContext "id" $id "resource" $merged) }}

    {{- $cleaned := omit $merged "nameOverride" "fullNameOverride" }}
    {{- include "resources.generic.render" (dict "apiVersion" $apiVersion "kind" $kind "contentIsSpec" $contentIsSpec "name" $fullName "resource" $cleaned) }}
  {{- end }}
{{- end }}
