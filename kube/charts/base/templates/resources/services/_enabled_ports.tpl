{{/*
Return the enabled ports for a given Service object.
*/}}
{{- define "base.resources.services.enabledPorts" -}}
  {{- $rootContext := .rootContext -}}
  {{- $serviceObject := .serviceObject -}}

  {{- $enabledPorts := dict -}}

  {{- range $name, $port := $serviceObject.ports -}}
    {{- if kindIs "map" $port -}}
      {{- if include "base.lib.utils.isEnabled" $port -}}
        {{- $_ := set $enabledPorts $name . -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $enabledPorts | toYaml -}}
{{- end -}}
