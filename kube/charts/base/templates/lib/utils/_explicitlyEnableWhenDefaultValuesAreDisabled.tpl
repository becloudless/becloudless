{{/*
  function to add `enable: true`, when not explicitly set, while enabled and default values as `enabled: false`, which would make the node disabled on merge
*/}}
{{- define "base.lib.utils.explicitlyEnableWhenDefaultValuesAreDisabled" -}}
  {{- $default := .default -}}
  {{- $current := .current -}}

  {{- if kindIs "map" $default -}}
    {{- if and (hasKey $default "enabled") (not $default.enabled) -}}
      {{- if and (not (hasKey $current "enabled")) (include "base.lib.utils.isEnabled" .)  -}}
        {{- $_ := set $current "enabled" true -}}
      {{- end -}}
    {{- end -}}

    {{- range $k, $v := $default -}}
      {{- if hasKey $current $k -}}
        {{- include "base.lib.utils.explicitlyEnableWhenDefaultValuesAreDisabled" (dict "default" $v "current" (get $current $k)) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
