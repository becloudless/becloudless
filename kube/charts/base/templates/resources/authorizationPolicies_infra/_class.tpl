{{- define "base.resources.authorizationPolicies.class" -}}
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
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- with $object.action }}
  action: {{ . }}
  {{- end }}
  {{- with $object.workloadLabels }}
  selector:
    matchLabels: {{- tpl (toYaml .) $rootContext | nindent 6 }}
  {{- end }}
  {{- with $object.rules }}
  rules: {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
