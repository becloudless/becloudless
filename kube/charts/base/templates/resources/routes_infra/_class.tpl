{{/*
This template serves as a blueprint for all Route objects that are created
within the common library.
*/}}
{{- define "base.resources.routes.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $routeKind := $object.kind | default "HTTPRoute" -}}
  {{- $apiVersion := "gateway.networking.k8s.io/v1alpha2" -}}
  {{- if $rootContext.Capabilities.APIVersions.Has (printf "gateway.networking.k8s.io/v1beta1/%s" $routeKind) }}
    {{- $apiVersion = "gateway.networking.k8s.io/v1beta1" -}}
  {{- end -}}
  {{- if $rootContext.Capabilities.APIVersions.Has (printf "gateway.networking.k8s.io/v1/%s" $routeKind) }}
    {{- $apiVersion = "gateway.networking.k8s.io/v1" -}}
  {{- end -}}
  {{- $labels := merge
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}
---
apiVersion: {{ $apiVersion }}
kind: {{ $routeKind }}
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  parentRefs:
  {{- range $object.parentRefs }}
    - group: {{ default "gateway.networking.k8s.io" .group }}
      kind: {{ default "Gateway" .kind }}
      name: {{ required (printf "parentRef name is required for %v %v" $routeKind $object.name) .name }}
      namespace: {{ required (printf "parentRef namespace is required for %v %v" $routeKind $object.name) .namespace }}
      {{- if .sectionName }}
      sectionName: {{ .sectionName | quote }}
      {{- end }}
  {{- end }}
  {{- if and (ne $routeKind "TCPRoute") (ne $routeKind "UDPRoute") $object.hostnames }}
  hostnames:
    {{- range $object.hostnames }}
    - {{ tpl . $rootContext | quote }}
    {{- end }}
  {{- end }}
  rules:
  {{- range $object.rules }}
  - backendRefs:
    {{- range .backendRefs }}
      {{ $service := include "base.resources.services.getByIdentifier" (dict "rootContext" $rootContext "id" .name) | fromYaml -}}
      {{ $servicePrimaryPort := dict -}}
      {{ if $service -}}
        {{ $servicePrimaryPort = include "base.resources.services.primaryPort" (dict "rootContext" $rootContext "serviceObject" $service) | fromYaml -}}
      {{- end }}
    - group: {{ default "" .group | quote}}
      kind: {{ default "Service" .kind }}
      name: {{ default .name $service.name }}
      namespace: {{ default $rootContext.Release.Namespace .namespace }}
      port: {{ default .port $servicePrimaryPort.port }}
      weight: {{ default 1 .weight }}
    {{- end }}
    {{- if or (eq $routeKind "HTTPRoute") (eq $routeKind "GRPCRoute") }}
      {{- with .matches }}
    matches:
        {{- toYaml . | nindent 6 }}
      {{- end }}
        {{- with .filters }}
    filters:
        {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- end }}
    {{- if (eq $routeKind "HTTPRoute") }}
      {{- with .timeouts }}
    timeouts:
        {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
