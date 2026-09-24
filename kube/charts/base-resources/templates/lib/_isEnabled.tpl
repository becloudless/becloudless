{{- define "base-resources.lib.isEnabled" }}
  {{- $enabled := not (empty .) -}}
  {{- if and (kindIs "map" .) (hasKey . "enabled") -}}
    {{- $enabled = .enabled -}}
  {{- end -}}
  {{- if or (and (kindIs "bool" $enabled) $enabled) (and (kindIs "string" $enabled) (not (eq $enabled "false"))) -}}
true
  {{- end -}}
{{- end }}
