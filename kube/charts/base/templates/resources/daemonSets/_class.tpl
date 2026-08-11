{{/*
This template serves as the blueprint for the DaemonSet objects that are created
within the common library.
*/}}
{{- define "base.resources.daemonSets.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $labels := merge
    (dict "app.kubernetes.io/component" $object.identifier)
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}
---
apiVersion: apps/v1
kind: DaemonSet
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
  selector:
    matchLabels:
      {{- if $rootContext.Values.global.legacyLabelSelector }}
      app: {{ include "base.lib.chart.names.name" $rootContext }}
      {{- else }}
      app.kubernetes.io/component: {{ $object.identifier }}
      {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 6 }}
      {{- end }}
  template:
    metadata:
      annotations: {{ include "base.resources.pods.metadata.annotations" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 8 }}
      labels: {{ include "base.resources.pods.metadata.labels" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 8 }}
    spec: {{ include "base.resources.pods.class" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 6 }}
{{- end }}
