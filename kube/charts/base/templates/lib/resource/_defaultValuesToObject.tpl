{{- define "base.lib.resource.defaultValuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- $_ := set $objectValues "name" (include "base.lib.resource.name" (dict "rootContext" $rootContext "id" $identifier "values" $objectValues)) -}}
  {{- $_ := set $objectValues "identifier" $identifier -}}
{{- end -}}
