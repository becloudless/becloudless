{{- /*
The global values shared with every installed app, computed from `config`.
Rendered as a `global-values` ConfigMap in the namespace of each app, used by the HelmRelease of the app as `valuesFrom`.
*/}}
{{- define "app-apps.globalValues" }}
{{- $rootContext := .rootContext }}

{{- $config := $rootContext.Values.config | default dict }}
{{- $domain := $config.domain }}
{{- if not $domain }}
  {{- fail "config.domain is required" }}
{{- end }}

{{- $name := $config.name }}
{{- if not $name }}
  {{- $name = lower (first (splitList "." $domain)) }}
{{- end }}

{{- $ldapdn := $config.ldapdn }}
{{- if not $ldapdn }}
  {{- $dcs := list }}
  {{- range splitList "." (lower $domain) }}
    {{- $dcs = append $dcs (printf "dc=%s" .) }}
  {{- end }}
  {{- $ldapdn = join "," $dcs }}
{{- end }}

{{- dict "global" (dict "domain" $domain "name" $name "ldapdn" $ldapdn "lldapUsers" ($config.lldapUsers | default dict)) | toYaml }}
{{- end }}
