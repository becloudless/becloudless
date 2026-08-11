{{/*
Return a container Object by its Identifier.
*/}}
{{- define "base.lib.container.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $controller := .controller -}}

  {{- $controllerValues := get $rootContext.Values.resources.controllers $controller -}}
  {{- if $controllerValues -}}
    {{- range $name, $containerValues := $controllerValues.containers -}}
      {{- if eq $name $identifier -}}
        {{- include "base.resources.containers.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $containerValues) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
