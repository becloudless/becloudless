{{/*
Convert DaemonSet values to an object
*/}}
{{- define "base.resources.daemonSets.valuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- $_ := set $objectValues.pod "serviceAccountName" (include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "serviceAccounts" "valuePrefix" "serviceAccountName" "optional" true "values" $objectValues.pod "failSuffix" (printf "controller: %s" $identifier))) -}}

  {{- /* Return the DaemonSet object */ -}}
  {{- $objectValues | toYaml -}}
{{- end -}}
