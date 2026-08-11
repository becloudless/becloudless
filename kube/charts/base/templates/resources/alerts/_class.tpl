{{/* class */}}
{{- define "base.resources.alerts.class" -}}
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
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  providerRef:
    name: {{ $object.provider }}
  {{-  with $object.eventSeverity }}
  eventSeverity: {{ . }}
  {{- end }}
  eventSources:
    {{- toYaml $object.eventSources | nindent 4 }}
  {{-  with $object.inclusionList }}
  inclusionList:
    {{/* use toYaml directly is not possible as it removes the quote. To add them back, we need this small trick with the range */}}
    {{- range $object.inclusionList -}}
    - {{ toYaml . | quote }}
    {{- end -}}
  {{- end }}
  eventMetadata:
    {{- toYaml $object.eventMetadata | nindent 4 }}
{{- end -}}
