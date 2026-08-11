{{/*
Convert StatefulSet values to an object
*/}}
{{- define "base.resources.statefulSets.valuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- $_ := set $objectValues.pod "serviceAccountName" (include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "serviceAccounts" "valuePrefix" "serviceAccountName" "optional" true "values" $objectValues.pod "failSuffix" (printf "controller: %s" $identifier))) -}}

  {{- /* Return the StatefulSet object */ -}}
  {{- $objectValues | toYaml -}}
{{- end -}}
