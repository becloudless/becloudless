{{/*
Return a secret Object by its Identifier.
*/}}
{{- define "base.resources.sealedSecrets.getByIdentifier" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}

  {{- $secretValues := dig "sealedSecrets" $identifier nil $rootContext.Values.resources -}}
  {{- if not (empty $secretValues) -}}
    {{- include "base.resources.sealedSecrets.valuesToObject" (dict "rootContext" $rootContext "id" $identifier "values" $secretValues) -}}
  {{- end -}}
{{- end -}}
