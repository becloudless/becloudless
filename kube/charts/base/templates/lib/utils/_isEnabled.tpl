{{/*
Tell if element is enabled with the `enabled: true/false` pattern.
By default it's enabled, as soon as the dict is not empty
*/}}
{{- define "base.lib.utils.isEnabled" -}}
  {{- $enabled := not (empty .) -}}
  {{- if and (kindIs "map" .) (hasKey . "enabled") -}}
    {{- $enabled = .enabled -}}
  {{- end -}}
  {{- if or (and (kindIs "bool" $enabled) $enabled) (and (kindIs "string" $enabled) (not (eq $enabled "false"))) -}}
true
  {{- end -}}
{{- end -}}
