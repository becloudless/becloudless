{{/*
This template serves as a blueprint for HorizontalPodAutoscaler objects that are created using the common library.
*/}}
{{- define "base.resources.horizontalPodAutoscalers.class" -}}
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
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ $object.controller.type }}
    name: {{ $object.controller.name }}
  minReplicas: {{ $object.minReplicas }}
  maxReplicas: {{ $object.maxReplicas }}
  {{- with $object.metrics }}
  metrics:
  {{- range $k, $v := . }}
    {{- if include "base.lib.utils.isEnabled" $v }}
      {{- $_ := unset $v "enabled" }}
      {{- toYaml (list $v) | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- end }}
  {{- if $object.behavior }}
  behavior: {{- toYaml $object.behavior | nindent 4 }}
  {{- end }}
{{- end -}}
