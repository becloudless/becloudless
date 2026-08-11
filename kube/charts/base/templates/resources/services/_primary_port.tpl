{{/*
Return the primary port for a given Service object.
*/}}
{{- define "base.resources.services.primaryPort" -}}
  {{- $rootContext := .rootContext -}}
  {{- $serviceObject := .serviceObject -}}
  {{- $result := "" -}}

  {{- /* Loop over all enabled ports */ -}}
  {{- $enabledPorts := include "base.resources.services.enabledPorts" (dict "rootContext" $rootContext "serviceObject" $serviceObject) | fromYaml }}
  {{- range $name, $port := $enabledPorts -}}
    {{- /* Determine the port that has been marked as primary */ -}}
    {{- if and (hasKey $port "primary") $port.primary -}}
      {{- $result = $port -}}
    {{- end -}}
  {{- end -}}

  {{- /* Return the first port if none has been explicitly marked as primary */ -}}
  {{- if not $result -}}
    {{- $firstPortKey := keys $enabledPorts | first -}}
    {{- if not $firstPortKey -}}
      {{- fail (printf "no ports are enabled for Service with id \"%s\"" $serviceObject.identifier) -}}
    {{- else -}}
    {{- $result = get $enabledPorts $firstPortKey -}}
    {{- end -}}
  {{- end -}}

  {{- $result | toYaml -}}
{{- end -}}
