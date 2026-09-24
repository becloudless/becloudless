{{- define "base-resources.renderResourceKind" }}
  {{- $rootContext := .rootContext }}
  {{- $name := .name }}
  {{- $apiVersion := .apiVersion }}
  {{- $kind := .kind }}
  {{- $contentIsSpec := true }}
  {{- if hasKey . "contentIsSpec" }}
    {{- $contentIsSpec = .contentIsSpec }}
  {{- end }}
  {{- $required := .required | default list }}
  {{- $stringifyFields := .stringifyFields | default list }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $defaultsResourcesAll := $defaultsAll.resources | default dict }}
  {{- $default := get $defaultsResourcesAll $name | default dict }}
  {{- $resourcesAll := $rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $name | default dict) }}
    {{- $merged := merge ($resource | default dict) $default }}
    {{- $merged = tpl (toYaml $merged) $rootContext | fromYaml }}
    {{- $merged = include "base-resources.stringifyFields" (dict "resource" $merged "stringifyFields" $stringifyFields) | fromYaml }}

    {{- if (include "base-resources.mutations.enabled" (dict "resource" $merged) | trim) -}}
      {{- $merged = omit $merged "enabled" }}
      {{- include "base-resources.mutations.required" (dict "name" $name "id" $id "resource" $merged "required" $required) }}

      {{- $metadata := include "base-resources.computeMetadata" (dict "rootContext" $rootContext "id" $id "resource" $merged) | trim }}
      {{- $cleaned := omit $merged "nameOverride" "fullNameOverride" "namespace" "labels" "annotations" "enabled" }}
      {{- include "base-resources.renderResource" (dict "apiVersion" $apiVersion "kind" $kind "contentIsSpec" $contentIsSpec "metadata" $metadata "resource" $cleaned) }}
    {{- end }}
  {{- end }}
{{- end }}
