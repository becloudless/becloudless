{{/*
Validate controller values
*/}}
{{- define "base.resources.controllers.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerValues := .object -}}

  {{- $allowedControllerTypes := list "Deployment" "DaemonSet" "StatefulSet" "CronJob" "Job" "InferenceService" -}}
  {{- if not (has $controllerValues.type $allowedControllerTypes) -}}
    {{- fail (printf "Not a valid controller.type (%s)" $controllerValues.type) -}}
  {{- end -}}

  {{- $enabledContainers := include "base.resources.controllers.enabledContainers" (dict "rootContext" $rootContext "controllerObject" $controllerValues) | fromYaml }}
  {{- /* Validate at least one container is enabled */ -}}
  {{- if not $enabledContainers -}}
    {{- fail (printf "No containers enabled for controller (%s)" $controllerValues.identifier) -}}
  {{- end -}}
{{- end -}}
