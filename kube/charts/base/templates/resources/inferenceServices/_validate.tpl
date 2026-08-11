{{/*
Validate InferenceService values
*/}}
{{- define "base.resources.inferenceServices.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $inferenceServiceObject := .object -}}

  {{- if ne (len $inferenceServiceObject.containers) 1 -}}
    {{- fail (printf "InferenceService controller type can only have one container declared. (controller: %s)" $inferenceServiceObject.identifier) -}}
  {{- end -}}

  {{- if not (dig "inferenceService" "predictor" "model" "storageUri" nil $inferenceServiceObject) -}}
    {{- fail (printf "inferenceService.predictor.model.storageUri field is required for controller. (controller: %s)" $inferenceServiceObject.identifier) -}}
  {{- end -}}

{{- end -}}
