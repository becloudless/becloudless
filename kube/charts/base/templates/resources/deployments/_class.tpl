{{/*
This template serves as a blueprint for Deployment objects that are created
using the common library.
*/}}
{{- define "base.resources.deployments.class" -}}
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
kind: Deployment
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
  strategy:
    type: {{ $object.strategy }}
    {{- with $object.rollingUpdate }}
      {{- if and (eq $object.strategy "RollingUpdate") (or .maxSurge .maxUnavailable) }}
    rollingUpdate:
        {{- if not (kindIs "invalid" .maxUnavailable) }}
      maxUnavailable: {{ .maxUnavailable }}
        {{- end }}
        {{- with .maxSurge }}
      maxSurge: {{ . }}
        {{- end }}
      {{- end }}
    {{- end }}
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
      {{- with (include "base.resources.pods.metadata.annotations" (dict "rootContext" $rootContext "controllerObject" $object)) }}
      annotations: {{- . | nindent 8 }}
      {{- end -}}
      {{- with (include "base.resources.pods.metadata.labels" (dict "rootContext" $rootContext "controllerObject" $object)) }}
      labels: {{- . | nindent 8 }}
      {{- end }}
    spec: {{- include "base.resources.pods.class" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 6 }}
{{- end -}}
