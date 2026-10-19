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
  {{- /* The kinds without namespace are cluster scoped: they get no metadata.namespace. */}}
  {{- $clusterScopedKinds := list "Namespace" "PersistentVolume" "StorageClass" "VolumeSnapshotClass" "ClusterRole" "ClusterRoleBinding" "GatewayClass" "ClusterIssuer" "ClusterPolicy" "ValidatingPolicy" "CiliumLoadBalancerIPPool" "CiliumBGPAdvertisement" "CiliumBGPPeerConfig" "CiliumBGPClusterConfig" }}
  {{- $labels := merge ($resource.labels | default dict) ($globalMetadataAll.labels | default dict) }}
  {{- $annotations := merge ($resource.annotations | default dict) ($globalMetadataAll.annotations | default dict) }}

  {{- $metadata := dict "name" $name }}
  {{- if not (has .kind $clusterScopedKinds) }}
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
