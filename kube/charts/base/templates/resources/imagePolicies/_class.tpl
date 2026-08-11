{{/*
This template serves as a blueprint for ImagePolicy objects that are created
using the common library.
*/}}
{{- define "base.resources.imagePolicies.class" -}}
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
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: {{ $object.name }}-{{ $rootContext.Release.Namespace }}
  namespace: flux-system
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  imageRepositoryRef:
    name: {{ $object.imageRepository.name }}
    namespace: {{ $rootContext.Release.Namespace }}
  policy:
    semver:
      range: {{ $object.semverRange }}
{{- end -}}
