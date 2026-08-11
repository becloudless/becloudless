{{/*
This template serves as a blueprint for all Ingress objects that are created
within the common library.
*/}}

{{- define "base.resources.ingresses.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $labels := merge
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- if $object.className }}
  ingressClassName: {{ $object.className }}
  {{- end }}
  {{- if $object.tls }}
  tls:
    {{- range $object.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ tpl . $rootContext | quote }}
        {{- end }}
      {{- $secretName := tpl (default "" .secretName) $rootContext }}
      {{- if $secretName }}
      secretName: {{ $secretName | quote}}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if $object.defaultBackend }}
  defaultBackend: {{ $object.defaultBackend }}
  {{- else }}
  rules:
  {{- range $object.hosts }}
    - host: {{ tpl .host $rootContext | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ tpl .path $rootContext | quote }}
            pathType: {{ default "Prefix" .pathType }}
            backend:
              service:
                {{ $service := include "base.resources.services.getByIdentifier" (dict "rootContext" $rootContext "id" .service.name) | fromYaml -}}
                {{ $servicePort := 0 -}}

                {{ if empty (dig "port" nil .service) -}}
                  {{/* Default to the Service primary port if no port has been specified */ -}}
                  {{ if $service -}}
                    {{ $defaultServicePort := include "base.resources.services.primaryPort" (dict "rootContext" $rootContext "serviceObject" $service) | fromYaml -}}
                    {{ if $defaultServicePort -}}
                      {{ $servicePort = $defaultServicePort.port -}}
                    {{ end -}}
                  {{ end -}}
                {{ else -}}
                  {{/* If a port number is given, use that */ -}}
                  {{ if kindIs "float64" .service.port -}}
                    {{ $servicePort = .service.port -}}
                  {{ else if kindIs "string" .service.port -}}
                    {{/* If a port name is given, try to resolve to a number */ -}}
                    {{ $servicePort = include "base.resources.services.getPortNumberByName" (dict "rootContext" $rootContext "serviceID" .service.name "portName" .service.port) -}}
                  {{ end -}}
                {{ end -}}
                name: {{ default .service.name $service.name }}
                port:
                  number: {{ $servicePort }}
          {{- end }}
  {{- end }}
  {{- end }}
{{- end }}
