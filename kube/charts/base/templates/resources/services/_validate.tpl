{{/*
Validate Service values
*/}}
{{- define "base.resources.services.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $serviceObject := .object -}}

  {{- if empty (get $serviceObject "controller") -}}
    {{- fail (printf "controller field is required for Service. (service: %s)" $serviceObject.identifier) -}}
  {{- end -}}

  {{- /* Validate Service type */ -}}
  {{- $validServiceTypes := (list "ClusterIP" "LoadBalancer" "NodePort" "ExternalName" "ExternalIP") -}}
  {{- if and $serviceObject.type (not (mustHas $serviceObject.type $validServiceTypes)) -}}
    {{- fail (
      printf "invalid service type \"%s\" for Service with key \"%s\". Allowed values are [%s]"
      $serviceObject.type
      $serviceObject.identifier
      (join ", " $validServiceTypes)
    ) -}}
  {{- end -}}

  {{- if ne $serviceObject.type "ExternalName" -}}
    {{- $enabledPorts := include "base.resources.services.enabledPorts" (dict "rootContext" $rootContext "serviceObject" $serviceObject) | fromYaml }}
    {{- /* Validate at least one port is enabled */ -}}
    {{- if not $enabledPorts -}}
      {{- fail (printf "no ports are enabled for Service with id \"%s\"" $serviceObject.identifier) -}}
    {{- end -}}

    {{- range $name, $port := $enabledPorts -}}
      {{- /* Validate a port number is configured */ -}}
      {{- if not $port.port -}}
        {{- fail (printf "no port number is configured for port \"%s\" under Service with key \"%s\"" $name $serviceObject.identifier) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
