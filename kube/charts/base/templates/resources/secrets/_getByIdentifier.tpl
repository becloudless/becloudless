{{/*
Return a secret Object by its Identifier.
*/}}
{{- define "base.resources.secrets.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- $secretValues := dig $identifier nil $rootContext.Values.secrets -}}
  {{- if not (empty $secretValues) -}}
    {{- include "base.resources.secrets.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $secretValues) -}}
  {{- end -}}
{{- end -}}
