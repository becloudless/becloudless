{{- define "base.resources.telemetries.class" -}}
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
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- with $object.workloadLabels }}
  selector:
    matchLabels: {{- toYaml . | nindent 6 }}
  {{- end }}
  {{- with $object.targetRef }}
  targetRef: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.tracing }}
  tracing: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.metrics }}
  metrics: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.accessLogging }}
  accessLogging: {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
