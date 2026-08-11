{{/* Return the name of the primary route object */}}
{{- define "base.resources.routes.primary" -}}
  {{- $enabledRoutes := dict -}}
  {{- range $name, $route := .Values.resources.routes -}}
    {{- if include "base.lib.utils.isEnabled" $route -}}
      {{- $_ := set $enabledRoutes $name . -}}
    {{- end -}}
  {{- end -}}

  {{- $result := "" -}}
  {{- range $name, $route := $enabledRoutes -}}
    {{- if and (hasKey $route "primary") $route.primary -}}
      {{- $result = $name -}}
    {{- end -}}
  {{- end -}}

  {{- if not $result -}}
    {{- $result = keys $enabledRoutes | first -}}
  {{- end -}}
  {{- $result -}}
{{- end -}}
