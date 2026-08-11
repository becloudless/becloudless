{{/*
This template serves as a blueprint for all SealedSecret objects that are created
within the common library.
*/}}
{{- define "base.resources.sealedSecrets.class" -}}
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

  {{- $encryptedData := "" -}}
  {{- with $object.encryptedData -}}
    {{- $encryptedData = (toYaml $object.encryptedData) | trim -}}
  {{- end -}}

---
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: {{ $object.name }}
  namespace: {{ default $rootContext.Release.Namespace $object.namespace }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
{{- with $encryptedData }}
  encryptedData:
    {{- . | nindent 4 }}
{{- end }}
  template:
    {{- with $object.type }}
    type: {{ . }}
    {{- end }}
    metadata:
      name: {{ $object.name }}
      {{- with $labels }}
      labels: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $annotations }}
      annotations: {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
