{{/*
Return a container Object by its Identifier.
*/}}
{{- define "base.resources.imageRepositories.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- range $name, $values := $rootContext.Values.resources.imageRepositories -}}
    {{- if eq $name $identifier -}}
      {{- include "base.resources.imageRepositories.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $values) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
