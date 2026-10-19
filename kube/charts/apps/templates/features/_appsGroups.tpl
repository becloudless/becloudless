{{- /*
Enable apps from the groups they belong to.

An app listing a group in `apps.<name>.groups` (`<group>: true`) gets `apps.<name>.enabled: true`
when `appsGroups.<group>.enabled` is true, `false` otherwise (a non-empty app without `enabled` is enabled for `base.lib.isEnabled`).
The result is used as a default: an explicit `apps.<name>.enabled` set by the user always wins.
*/}}
{{- define "app-apps.features.appsGroups" }}
{{- $rootContext := .rootContext }}

{{- $appsGroups := $rootContext.Values.appsGroups | default dict }}

{{- $apps := dict }}
{{- range $name, $app := ($rootContext.Values.apps | default dict) }}
  {{- $groups := ($app | default dict).groups | default dict }}
  {{- if $groups }}
    {{- $enabled := false }}
    {{- range $group, $member := $groups }}
      {{- if and $member (include "base.lib.isEnabled" (get $appsGroups $group) | trim) }}
        {{- $enabled = true }}
      {{- end }}
    {{- end }}
    {{- $_ := set $apps $name (dict "enabled" $enabled) }}
  {{- end }}
{{- end }}

{{- dict "apps" $apps | toYaml }}
{{- end }}
