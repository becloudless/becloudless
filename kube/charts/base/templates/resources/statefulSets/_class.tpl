{{/*
This template serves as the blueprint for the StatefulSet objects that are created
within the common library.
*/}}
{{- define "base.resources.statefulSets.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $labels := merge
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  revisionHistoryLimit: {{ $object.revisionHistoryLimit }}
  {{- if not (eq $object.replicas nil) }}
  replicas: {{ $object.replicas }}
  {{- end }}
  podManagementPolicy: {{ dig "statefulSet" "podManagementPolicy" "OrderedReady" $object }}
  updateStrategy:
    type: {{ $object.strategy }}
    {{- if and (eq $object.strategy "RollingUpdate") (dig "rollingUpdate" "partition" nil $object) }}
    rollingUpdate:
      partition: {{ $object.rollingUpdate.partition }}
    {{- end }}
  selector:
    matchLabels:
      {{- if $rootContext.Values.global.legacyLabelSelector }}
      app: {{ include "base.lib.chart.names.name" $rootContext }}
      {{- else }}
      app.kubernetes.io/component: {{ $object.identifier }}
      {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 6 }}
      {{- end }}
  serviceName: {{ include "base.lib.chart.names.fullname" $rootContext }}
  template:
    metadata:
      {{- with (include "base.resources.pods.metadata.annotations" (dict "rootContext" $rootContext "controllerObject" $object)) }}
      annotations: {{ . | nindent 8 }}
      {{- end -}}
      {{- with (include "base.resources.pods.metadata.labels" (dict "rootContext" $rootContext "controllerObject" $object)) }}
      labels: {{ . | nindent 8 }}
      {{- end }}
    spec: {{ include "base.resources.pods.class" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 6 }}
  {{- with (include "base.lib.statefulset.volumeclaimtemplates" (dict "rootContext" $rootContext "statefulSetObject" $object)) }}
  volumeClaimTemplates: {{ . | nindent 4 }}
  {{- end }}
{{- end }}
