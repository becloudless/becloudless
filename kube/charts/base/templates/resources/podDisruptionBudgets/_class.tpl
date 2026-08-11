{{/*
This template serves as a blueprint for PodDisruptionBudget objects that are created using the common library.
*/}}
{{- define "base.resources.podDisruptionBudgets.class" -}}
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
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- with $object.minAvailable }}
  minAvailable: {{ . }}
  {{- end }}
  {{- with $object.maxUnavailable }}
  maxUnavailable: {{ . }}
  {{- end }}
  {{- with (merge
    ($object.extraSelectorLabels | default dict)
    (dict "app.kubernetes.io/component" $object.controller)
    (include "base.lib.metadata.selectorLabels" $rootContext | fromYaml)
  ) }}
  selector:
    matchLabels:
      {{- toYaml . | nindent 6 }}
  {{- end }}
{{- end -}}
