{{/*
This template serves as a blueprint for Cronjob objects that are created
using the common library.
*/}}
{{- define "base.resources.cronJobs.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $timeZone := "" -}}
  {{- if ge (int $rootContext.Capabilities.KubeVersion.Minor) 27 }}
    {{- $timeZone = dig "cronJob" "timeZone" "" $object -}}
  {{- end -}}

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
kind: CronJob
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- with $object.cronJob.suspend }}
  suspend: {{ ternary "true" "false" . }}
  {{- end }}
  concurrencyPolicy: "{{ $object.cronJob.concurrencyPolicy }}"
  startingDeadlineSeconds: {{ $object.cronJob.startingDeadlineSeconds }}
  {{- with $timeZone }}
  timeZone: "{{ . }}"
  {{- end }}
  schedule: "{{ tpl $object.cronJob.schedule $rootContext }}"
  successfulJobsHistoryLimit: {{ $object.cronJob.successfulJobsHistory }}
  failedJobsHistoryLimit: {{ $object.cronJob.failedJobsHistory }}
  jobTemplate:
    spec:
      {{- with $object.cronJob.activeDeadlineSeconds }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      {{- with $object.cronJob.ttlSecondsAfterFinished }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
      backoffLimit: {{ $object.cronJob.backoffLimit }}
      template:
        metadata:
          {{- with (include "base.resources.pods.metadata.annotations" (dict "rootContext" $rootContext "controllerObject" $object)) }}
          annotations: {{- . | nindent 12 }}
          {{- end -}}
          {{- with (include "base.resources.pods.metadata.labels" (dict "rootContext" $rootContext "controllerObject" $object)) }}
          labels: {{- . | nindent 12 }}
          {{- end }}
        spec: {{- include "base.resources.pods.class" (dict "rootContext" $rootContext "controllerObject" $object) | nindent 10 }}
{{- end -}}
