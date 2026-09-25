{{- define "base-resources.computeMetadata" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}

  {{- $name := include "base-resources.lib.computeResourceName" (dict "rootContext" $rootContext "id" $id "resource" $resource) }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $globalMetadataAll := $defaultsAll.metadata | default dict }}
  {{- $globalMetadataAll = tpl (toYaml $globalMetadataAll) $rootContext | fromYaml }}
  {{- $namespace := $resource.namespace | default $globalMetadataAll.namespace | default $rootContext.Release.Namespace }}
  {{- $labels := merge ($resource.labels | default dict) ($globalMetadataAll.labels | default dict) }}
  {{- $annotations := merge ($resource.annotations | default dict) ($globalMetadataAll.annotations | default dict) }}
metadata:
  name: {{ $name }}
  namespace: {{ $namespace }}
  {{- if $labels }}
  labels:
    {{- toYaml $labels | nindent 4 }}
  {{- end }}
  {{- if $annotations }}
  annotations:
    {{- toYaml $annotations | nindent 4 }}
  {{- end }}
{{- end }}
