{{- define "base.resources.persistentVolumes.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- if not $object.accessModes }}
    {{- fail (printf "accessModes is required (persistentVolume %s)" $object.identifier) }}
  {{- end }}

  {{- if not $object.size }}
    {{- fail (printf "size is required (persistentVolume %s)" $object.identifier) }}
  {{- end }}

  {{- if and $object.csi (not $object.csi.driver) }}
    {{- fail (printf "csi.driver is required (persistentVolume %s)" $object.identifier) }}
  {{- end }}

  {{- if and $object.csi (not $object.csi.volumeHandle) }}
    {{- fail (printf "csi.volumeHandle is required (persistentVolume %s)" $object.identifier) }}
  {{- end }}

{{- end -}}
