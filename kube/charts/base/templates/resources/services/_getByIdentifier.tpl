{{/*
Return a service Object by its Identifier.
*/}}
{{- define "base.resources.services.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- range $name, $serviceValues := $rootContext.Values.resources.services -}}
    {{- if eq $name $identifier -}}
      {{- include "base.resources.services.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $serviceValues) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
