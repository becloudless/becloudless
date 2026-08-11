{{- define "base.resources.envoyFilters.class" -}}
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
apiVersion: envoyFilter.istio.io/v1alpha1
kind: EnvoyFilter
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
  workloadSelector:
    labels: {{- toYaml . | nindent 6 }}
  {{- end }}
  {{- with $object.configPatches }}
  configPatches: {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
