{{- define "resources.generic.renderAll" }}
  {{- $rootContext := .rootContext }}
  {{- $name := .name }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentIsSpec := true }}
  {{- if hasKey . "contentIsSpec" }}
    {{- $contentIsSpec = .contentIsSpec }}
  {{- end }}
  {{- $required := .required | default list }}

  {{- $defaultsAll := $rootContext.Values.defaultValues | default dict }}
  {{- $default := get $defaultsAll $name | default dict }}
  {{- $resourcesAll := $rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $name | default dict) }}
    {{- $merged := merge ($resource | default dict) $default }}
    {{- include "resources.generic.requireFields" (dict "name" $name "id" $id "resource" $merged "required" $required) }}

    {{- $metadata := include "resources.generic.computeMetadata" (dict "rootContext" $rootContext "id" $id "resource" $merged) | trim }}
    {{- $cleaned := omit $merged "nameOverride" "fullNameOverride" "namespace" "labels" "annotations" }}
    {{- include "resources.generic.render" (dict "apiVersion" $apiVersion "kind" $kind "contentIsSpec" $contentIsSpec "metadata" $metadata "resource" $cleaned) }}
  {{- end }}
{{- end }}
