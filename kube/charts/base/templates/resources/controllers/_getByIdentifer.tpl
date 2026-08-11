{{/*
Return a controller Object by its Identifier.
*/}}
{{- define "base.resources.controllers.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- range $name, $controllerValues := $rootContext.Values.resources.controllers -}}
    {{- if eq $name $identifier -}}
      {{- include "base.resources.controllers.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $controllerValues) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
