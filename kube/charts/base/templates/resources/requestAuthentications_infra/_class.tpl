{{- define "base.resources.requestAuthentications.class" -}}
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
apiVersion: security.istio.io/v1
kind: RequestAuthentication
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
  jwtRules:
  - issuer: https://blablacar.onelogin.com/oidc/2
    jwksUri: https://blablacar.onelogin.com/oidc/2/certs
    forwardOriginalToken: true
{{- end -}}