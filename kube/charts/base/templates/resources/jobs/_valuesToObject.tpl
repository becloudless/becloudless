{{/*
Convert job values to an object
*/}}
{{- define "base.resources.jobs.valuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- $restartPolicy := default "Never" $objectValues.pod.restartPolicy -}}
  {{- $_ := set $objectValues.pod "restartPolicy" $restartPolicy -}}

  {{- $_ := set $objectValues.pod "serviceAccountName" (include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "serviceAccounts" "valuePrefix" "serviceAccountName" "optional" true "values" $objectValues.pod "failSuffix" (printf "controller: %s" $identifier))) -}}

  {{- /* Return the Job object */ -}}
  {{- $objectValues | toYaml -}}
{{- end -}}
