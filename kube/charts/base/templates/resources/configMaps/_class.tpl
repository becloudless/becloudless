{{/*
This template serves as a blueprint for all configMap objects that are created
within the common library.
*/}}
{{- define "base.resources.configMaps.class" -}}
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
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
data:
  {{- range $k, $v := $object.data }}
    {{- $res := dict $k $v }}
    {{- if kindIs "map" $v }}
      {{- $_ := set $res $k (toYaml (get $res $k)) }}
    {{- end }}
    {{- if not $object.noTemplating }}
      {{- $_ := set $res $k (tpl (get $res $k) $rootContext) }}
    {{- end }}
  {{- toYaml $res | nindent 2 }}
  {{- end }}
{{- end -}}
