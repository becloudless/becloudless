{{/*
This template serves as a blueprint for InferenceService objects that are created
using the base library.
*/}}
{{- define "base.resources.inferenceServices.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $labels := merge
    (dict "app.kubernetes.io/component" $object.identifier)
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}

  {{- $containerValues := (values $object.containers | first) -}}
  {{- $containerObject := (include "base.resources.containers.valuesToObject" (dict "rootContext" $rootContext "id" "main" "values" $containerValues)) | fromYaml -}}
  {{- include "base.resources.containers.validate" (dict "rootContext" $rootContext "controllerObject" $object "containerObject" $containerObject) -}}

---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  predictor:
    {{- with $object.inferenceService.predictor.minReplicas }}
    minReplicas: {{ . }}
    {{- end }}
    {{- with $object.inferenceService.predictor.maxReplicas }}
    maxReplicas: {{ . }}
    {{- end }}
    {{- with $object.inferenceService.predictor.scaleTarget }}
    scaleTarget: {{ . }}
    {{- end }}
    {{- with $object.inferenceService.predictor.scaleMetric }}
    scaleMetric: {{ . }}
    {{- end }}
    {{- include "base.resources.pods.class" (dict "rootContext" $rootContext "controllerObject" $object "doNotRenderContainers" true) | nindent 4 }}
    model:
      {{- include "base.resources.containers.class" (dict "rootContext" $rootContext "controllerObject" $object "containerObject" $containerObject) | nindent 6 }}
      {{- with $object.inferenceService.predictor.model.modelFormat }}
      modelFormat:
        name: {{ .name }}
      {{- end }}
      protocolVersion: {{ $object.inferenceService.predictor.model.protocolVersion }}
      storageUri: {{ $object.inferenceService.predictor.model.storageUri }}
{{- end -}}
