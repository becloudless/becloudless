{{- define "base-resources.mutations.metadata" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
  {{- $object := .object | default dict }}

  {{- $name := include "base-resources.lib.computeResourceName" (dict "rootContext" $rootContext "id" $id "resource" $resource) }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $globalMetadataAll := $defaultsAll.metadata | default dict }}
  {{- $globalMetadataAll = tpl (toYaml $globalMetadataAll) $rootContext | fromYaml }}
  {{- $namespace := $resource.namespace | default $globalMetadataAll.namespace | default $rootContext.Release.Namespace }}
  {{- $labels := merge ($resource.labels | default dict) ($globalMetadataAll.labels | default dict) }}
  {{- $annotations := merge ($resource.annotations | default dict) ($globalMetadataAll.annotations | default dict) }}

  {{- $metadata := dict "name" $name "namespace" $namespace }}
  {{- if $labels }}
    {{- $metadata = set $metadata "labels" $labels }}
  {{- end }}
  {{- if $annotations }}
    {{- $metadata = set $metadata "annotations" $annotations }}
  {{- end }}

  {{- $object = set $object "metadata" $metadata }}
  {{- toYaml $object }}
{{- end }}
