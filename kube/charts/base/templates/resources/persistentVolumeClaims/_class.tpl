{{/*
This template serves as a blueprint for all PersistentVolumeClaim objects that are created
within the common library.
*/}}
{{- define "base.resources.persistentVolumeClaims.class" -}}
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
  {{- if $object.retain }}
    {{- $annotations = merge
      (dict "helm.sh/resource-policy" "keep")
      $annotations
    -}}
  {{- end -}}

---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  accessModes:
    - {{ required (printf "accessMode is required for PVC %v" $object.name) $object.accessMode | quote }}
  resources:
    requests:
      storage: {{ required (printf "size is required for PVC %v" $object.name) $object.size | quote }}
  {{- if $object.storageClass }}
  storageClassName: {{ if (eq "-" $object.storageClass) }}""{{- else }}{{ $object.storageClass | quote }}{{- end }}
  {{- end }}
  {{- if $object.volumeName }}
  volumeName: {{ $object.volumeName | quote }}
  {{- end }}
  {{- with $object.dataSource }}
  dataSource: {{- tpl (toYaml .) $rootContext | nindent 10 }}
  {{- end }}
  {{- with $object.dataSourceRef }}
  dataSourceRef: {{- tpl (toYaml .) $rootContext | nindent 10 }}
  {{- end }}
{{- end -}}
