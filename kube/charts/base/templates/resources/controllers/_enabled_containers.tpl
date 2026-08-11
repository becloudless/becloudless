{{/*
Return the enabled containers for a controller.
*/}}
{{- define "base.resources.controllers.enabledContainers" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerObject := .controllerObject -}}

  {{- $enabledContainers := dict -}}
  {{- range $name, $container := $controllerObject.containers -}}
    {{- if kindIs "map" $container -}}
      {{- if include "base.lib.utils.isEnabled" $container -}}
        {{- $_ := set $enabledContainers $name $container -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- $enabledContainers | toYaml -}}
{{- end -}}
