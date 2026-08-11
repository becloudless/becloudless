{{/*
Convert Cronjob values to an object
*/}}
{{- define "base.resources.cronJobs.valuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- if not (hasKey $objectValues "pod") -}}
    {{- $_ := set $objectValues "pod" dict -}}
  {{- end -}}

  {{- $restartPolicy := default "Never" $objectValues.pod.restartPolicy -}}
  {{- $_ := set $objectValues.pod "restartPolicy" $restartPolicy -}}

  {{- $_ := set $objectValues.pod "serviceAccountName" (include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "serviceAccounts" "valuePrefix" "serviceAccountName" "optional" true "values" $objectValues.pod "failSuffix" (printf "controller: %s" $identifier))) -}}

  {{- /* Return the CronJob object */ -}}
  {{- $objectValues | toYaml -}}
{{- end -}}
