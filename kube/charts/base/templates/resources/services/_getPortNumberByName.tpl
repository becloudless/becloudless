{{/*
Return a service port number by name for a Service object
*/}}
{{- define "base.resources.services.getPortNumberByName" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .serviceID -}}
  {{- $portName := .portName -}}

  {{- $service := include "base.resources.services.getByIdentifier" (dict "rootContext" $rootContext "id" $identifier) | fromYaml -}}

  {{- if $service -}}
    {{ $servicePort := dig "ports" $portName "port" nil $service -}}
    {{- if not (eq $servicePort nil) -}}
      {{- $servicePort -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
