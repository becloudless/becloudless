{{/*
This template serves as a blueprint for all sidecar objects that are created
within the common library.
*/}}
{{- define "base.resources.sidecars.class" -}}
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
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  workloadSelector:
    labels: {{- tpl (toYaml $object.workloadLabels) $rootContext | nindent 6 }}
  outboundTrafficPolicy:
    {{- if $object.blockUndefinedOutbound }}
    mode: "REGISTRY_ONLY"
    {{- else }}
    mode: "ALLOW_ANY"
    {{- end }}
  {{- with $object.egress }}
  egress: {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.ingress }}
  ingress: {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
