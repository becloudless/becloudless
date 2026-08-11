{{/* Return the name of the primary Ingress object */}}
{{- define "base.resources.ingresses.primary" -}}
  {{- $enabledIngresses := dict -}}
  {{- range $name, $ingress := .Values.resources.ingresses -}}
    {{- if include "base.lib.utils.isEnabled" $ingress -}}
      {{- $_ := set $enabledIngresses $name . -}}
    {{- end -}}
  {{- end -}}

  {{- $result := "" -}}
  {{- range $name, $ingress := $enabledIngresses -}}
    {{- if and (hasKey $ingress "primary") $ingress.primary -}}
      {{- $result = $name -}}
    {{- end -}}
  {{- end -}}

  {{- if not $result -}}
    {{- $result = keys $enabledIngresses | first -}}
  {{- end -}}
  {{- $result -}}
{{- end -}}
