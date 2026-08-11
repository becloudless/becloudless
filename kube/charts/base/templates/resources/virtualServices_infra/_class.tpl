
{{- define "base.resources.virtualServices.class" -}}
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
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- with $object.hosts }}
  hosts:
    {{- tpl (toYaml .) $rootContext | nindent 4 }}
  {{- end }}
  {{- with $object.exportTo }}
  exportTo:
    {{-  tpl (toYaml .) $rootContext | nindent 4 }}
  {{- end }}
  {{- with $object.gateways }}
  gateways:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.http }}
  http:
    {{- tpl (toYaml .) $rootContext | nindent 4 }}
  {{- end }}
  {{- with $object.tcp }}
  tcp:
    {{- tpl (toYaml .) $rootContext | nindent 4 }}
  {{- end }}
{{- end -}}
