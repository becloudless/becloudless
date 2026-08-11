{{/*
This template serves as a blueprint for all networkPolicy objects that are created
within the common library.
*/}}
{{- define "base.resources.networkPolicies.class" -}}
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
  {{- $podSelector := dict -}}
  {{- if (hasKey $object "podSelector") -}}
    {{- $podSelector = $object.podSelector -}}
  {{- else -}}
    {{- $podSelector = dict "matchLabels" (merge
      ($object.extraSelectorLabels | default dict)
      (dict "app.kubernetes.io/component" $object.controller)
      (include "base.lib.metadata.selectorLabels" $rootContext | fromYaml)
    ) -}}
  {{- end -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  podSelector: {{- toYaml $podSelector | nindent 4 }}
  {{- with $object.policyTypes }}
  policyTypes: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $object.rules.ingress }}
  ingress: {{- tpl (toYaml .) $rootContext | nindent 4 -}}
  {{- end }}
  {{- with $object.rules.egress }}
  egress: {{- tpl (toYaml .) $rootContext | nindent 4 -}}
  {{- end }}
{{- end -}}
