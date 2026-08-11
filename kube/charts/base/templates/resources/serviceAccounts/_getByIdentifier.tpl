{{/*
Return a secret Object by its Identifier.
*/}}
{{- define "base.resources.serviceAccounts.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- $secretValues := dig $identifier nil $rootContext.Values.resources.serviceAccounts -}}
  {{- if not (empty $secretValues) -}}
    {{- include "base.resources.serviceAccounts.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $secretValues) -}}
  {{- end -}}
{{- end -}}
