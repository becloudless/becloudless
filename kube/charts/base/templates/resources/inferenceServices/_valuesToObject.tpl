{{/*
Convert InferenceService values to an object
*/}}
{{- define "base.resources.inferenceServices.valuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- $_ := set $objectValues.pod "serviceAccountName" (include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "serviceAccounts" "valuePrefix" "serviceAccountName" "optional" true "values" $objectValues.pod "failSuffix" (printf "controller: %s" $identifier))) -}}

  {{- /* Return the InferenceService object */ -}}
  {{- $objectValues | toYaml -}}
{{- end -}}
