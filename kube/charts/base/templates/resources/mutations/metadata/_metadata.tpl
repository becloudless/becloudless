{{- define "base.resources.mutations.metadata" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $work := .work }}
  {{- $resource := $work.resource | default dict }}
  {{- $object := $work.object | default dict }}

  {{- $name := include "base.lib.computeResourceName" (dict "rootContext" $rootContext "id" $id "resource" $resource) }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $globalMetadataAll := $defaultsAll.metadata | default dict }}
  {{- $globalMetadataAll = tpl (toYaml $globalMetadataAll) $rootContext | fromYaml }}
  {{- $namespace := $resource.namespace | default $globalMetadataAll.namespace | default $rootContext.Release.Namespace }}
  {{- /* The cluster scoped kinds (`clusterScoped: true` in resources.yaml) get no metadata.namespace. */}}
  {{- $labels := merge ($resource.labels | default dict) ($globalMetadataAll.labels | default dict) }}
  {{- $annotations := merge ($resource.annotations | default dict) ($globalMetadataAll.annotations | default dict) }}

  {{- $metadata := dict "name" $name }}
  {{- if not .clusterScoped }}
    {{- $metadata = set $metadata "namespace" $namespace }}
  {{- end }}
  {{- if $labels }}
    {{- $metadata = set $metadata "labels" $labels }}
  {{- end }}
  {{- if $annotations }}
    {{- $metadata = set $metadata "annotations" $annotations }}
  {{- end }}

  {{- $object = set $object "metadata" $metadata }}
  {{- $work = set $work "object" $object }}
  {{- toYaml $work }}
{{- end }}
