
{{- define "base.resources.destinationRules.class" -}}
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
kind: DestinationRule
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}

spec:
  {{- with $object.host }}
  host: {{ tpl (toYaml .) $rootContext }}
  {{- end }}
  {{- with $object.exportTo }}
  exportTo:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.trafficPolicy }}
  trafficPolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.subsets }}
  subsets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
