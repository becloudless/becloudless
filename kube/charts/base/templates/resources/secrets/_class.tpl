{{/*
This template serves as a blueprint for all Secret objects that are created
within the common library.
*/}}
{{- define "base.resources.secrets.class" -}}
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

  {{- $stringData := "" -}}
  {{- with $object.stringData -}}
    {{- $stringData = (toYaml $object.stringData) | trim -}}
  {{- end -}}
---
apiVersion: v1
kind: Secret
{{- with $object.type }}
type: {{ . }}
{{- end }}
metadata:
  name: {{ $object.name }}
  namespace: {{ default $rootContext.Release.Namespace $object.namespace }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
{{- with $stringData }}
stringData: {{- tpl $stringData $rootContext | nindent 2 }}
{{- end }}
{{- end -}}
