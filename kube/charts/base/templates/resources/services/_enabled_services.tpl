{{/*
Return the enabled services.
*/}}
{{- define "base.resources.services.enabledServices" -}}
  {{- $rootContext := .rootContext -}}
  {{- $enabledServices := dict -}}

  {{- range $name, $service := $rootContext.Values.resources.services -}}
    {{- if kindIs "map" $service -}}
      {{- if include "base.lib.utils.isEnabled" $service -}}
        {{- $_ := set $enabledServices $name . -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- $enabledServices | toYaml -}}
{{- end -}}
