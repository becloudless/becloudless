{{- /*
Enable apps from the groups they belong to.

An app listing a group in `apps.<name>.groups` gets `apps.<name>.enabled: true` when `appsGroups.<group>.enabled` is true.
The result is used as a default: an explicit `apps.<name>.enabled` set by the user always wins.
*/}}
{{- define "app-bcl.features.appsGroups" }}
{{- $rootContext := .rootContext }}

{{- $appsGroups := $rootContext.Values.appsGroups | default dict }}

{{- $apps := dict }}
{{- range $name, $app := ($rootContext.Values.apps | default dict) }}
  {{- range $group := (($app | default dict).groups | default list) }}
    {{- if (get $appsGroups $group | default dict).enabled }}
      {{- $_ := set $apps $name (dict "enabled" true) }}
    {{- end }}
  {{- end }}
{{- end }}

{{- dict "apps" $apps | toYaml }}
{{- end }}
