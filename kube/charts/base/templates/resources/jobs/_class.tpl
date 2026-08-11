{{/*
This template serves as the blueprint for the job objects that are created
within the common library.
*/}}
{{- define "base.resources.jobs.class" -}}
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
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- with $object.job.activeDeadlineSeconds }}
  activeDeadlineSeconds: {{ . }}
  {{- end }}
  {{- with $object.job.suspend }}
  suspend: {{ ternary "true" "false" . }}
  {{- end }}
  {{- with $object.job.ttlSecondsAfterFinished }}
  ttlSecondsAfterFinished: {{ . }}
  {{- end }}
  backoffLimit: {{ $object.job.backoffLimit }}
  template:
    metadata:
      {{- with (include "base.resources.pods.metadata.annotations" (dict "rootContext" $rootContext "controllerObject" $object)) }}
      annotations: {{ . | nindent 8 }}
      {{- end -}}
      {{- with (include "base.resources.pods.metadata.labels" (dict "rootContext" $rootContext "controllerObject" $object)) }}
      labels: {{ . | nindent 8 }}
      {{- end }}
    spec: {{ include "base.resources.pods.class" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 6 }}
{{- end -}}
