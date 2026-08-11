{{- define "base.resources.persistentVolumes.class" -}}
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
kind: PersistentVolume
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
  {{- if $object.accessModes }}
    {{- $object.accessModes | toYaml | nindent 4 }}
  {{- end }}
  capacity:
    storage: {{ $object.size }}
  {{- if $object.storageClassName }}
  storageClassName: {{ if (eq "-" $object.storageClassName) }}""{{- else }}{{ $object.storageClassName | quote }}{{- end }}
  {{- end }}
  {{- if $object.persistentVolumeReclaimPolicy }}
  persistentVolumeReclaimPolicy: {{ $object.persistentVolumeReclaimPolicy }}
  {{- end }}
  {{- if $object.volumeMode }}
  volumeMode: {{ $object.volumeMode }}
  {{- end }}
  {{- if $object.nodeAffinity }}
  nodeAffinity:
    {{- $object.nodeAffinity | toYaml | nindent 4 }}
  {{- end }}
  {{- if $object.csi }}
  csi:
    {{- $object.csi | toYaml | nindent 4 }}
  {{- end }}

{{- end -}}
