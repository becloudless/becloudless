{{/*
Renders the serviceAccount object required by the chart.
*/}}
{{- define "base.resources.serviceAccounts.render" -}}
  {{- /* Generate named resource as required */ -}}
  {{- range $key, $sa := .Values.resources.serviceAccounts }}
    {{- if include "base.lib.utils.isEnabled" $sa -}}
      {{- $saValues := (mustDeepCopy $sa) -}}

      {{- /* Create object from the raw values */ -}}
      {{- $saObject := (include "base.resources.serviceAccounts.valuesToObject" (dict "rootContext" $ "id" $key "values" $saValues)) | fromYaml -}}

      {{- $secretId := (include "base.lib.resource.resourceId" (dict "workloadId" $key "resourceName" "sa-token")) -}}
      {{- $secretNameOverride := include "base.lib.resource.resourceNameOverride" (dict "workloadId" $key "relatedResourceNameOverride" $saObject.nameOverride "resourceSuffix" "sa-token") -}}
      {{- $secretValues := (dict "enabled" true "nameOverride" $secretNameOverride  "annotations" (dict "kubernetes.io/service-account.name" $saObject.name) "type" "kubernetes.io/service-account-token" ) -}}
      {{- $_ := set $saObject "secretName" (include "base.lib.resource.name" (dict "rootContext" $ "id" $secretId "values" $secretValues)) -}}

      {{- /* Perform validations on the resource before rendering */ -}}
      {{- include "base.resources.serviceAccounts.validate" (dict "rootContext" $ "object" $saObject) -}}

      {{/* Include the class */}}
      {{- include "base.resources.serviceAccounts.class" (dict "rootContext" $ "object" $saObject) | nindent 0 -}}


      {{- /* Create object from the raw Secret values */ -}}
      {{- $secretObject := (include "base.resources.secrets.valuesToObject" (dict "rootContext" $ "id" $secretId "values" $secretValues)) | fromYaml -}}

      {{- /* Perform validations on the Secret before rendering */ -}}
      {{- include "base.resources.secrets.validate" (dict "rootContext" $ "object" $secretObject) -}}

      {{/* Include the Secret class */}}
      {{- include "base.resources.secrets.class" (dict "rootContext" $ "object" $secretObject) | nindent 0 -}}


    {{- end -}}
  {{- end -}}
{{- end -}}
