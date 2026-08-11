{{/*
This template serves as a blueprint for all Service objects that are created
within the common library.
*/}}
{{- define "base.resources.services.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $svcType := $object.type | default "" -}}
  {{- $enabledPorts := include "base.resources.services.enabledPorts" (dict "rootContext" $rootContext "serviceObject" $object) | fromYaml }}
  {{- $labels := merge
    (dict "app.kubernetes.io/service" $object.name)
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  {{- if (or (eq $svcType "ClusterIP") (empty $svcType)) }}
  type: ClusterIP
  {{- if $object.clusterIP }}
  clusterIP: {{ $object.clusterIP }}
  {{end}}
  {{- else if eq $svcType "LoadBalancer" }}
  type: {{ $svcType }}
  {{- if $object.loadBalancerIP }}
  loadBalancerIP: {{ $object.loadBalancerIP }}
  {{- end }}
  {{- if $object.loadBalancerSourceRanges }}
  loadBalancerSourceRanges:
    {{ toYaml $object.loadBalancerSourceRanges | nindent 4 }}
  {{- end -}}
  {{- else }}
  type: {{ $svcType }}
  {{- end }}
  {{- if $object.externalTrafficPolicy }}
  externalTrafficPolicy: {{ $object.externalTrafficPolicy }}
  {{- end }}
  {{- if hasKey $object "allocateLoadBalancerNodePorts" }}
  allocateLoadBalancerNodePorts: {{ $object.allocateLoadBalancerNodePorts }}
  {{- end }}
  {{- if $object.sessionAffinity }}
  sessionAffinity: {{ $object.sessionAffinity }}
  {{- if $object.sessionAffinityConfig }}
  sessionAffinityConfig:
    {{ toYaml $object.sessionAffinityConfig | nindent 4 }}
  {{- end -}}
  {{- end }}
  {{- with $object.externalIPs }}
  externalIPs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if $object.publishNotReadyAddresses }}
  publishNotReadyAddresses: {{ $object.publishNotReadyAddresses }}
  {{- end }}
  {{- if $object.ipFamilyPolicy }}
  ipFamilyPolicy: {{ $object.ipFamilyPolicy }}
  {{- end }}
  {{- with $object.ipFamilies }}
  ipFamilies:
    {{ toYaml . | nindent 4 }}
  {{- end }}
  ports:
  {{- range $name, $port := $enabledPorts }}
    - port: {{ $port.port }}
      targetPort: {{ $port.targetPort | default $port.port }}
        {{- if $port.protocol }}
          {{- if or ( eq $port.protocol "HTTP" ) ( eq $port.protocol "HTTPS" ) ( eq $port.protocol "TCP" ) }}
      protocol: TCP
          {{- else }}
      protocol: {{ $port.protocol }}
          {{- end }}
        {{- else }}
      protocol: TCP
        {{- end }}
      name: {{ $name }}
        {{- if (and (eq $svcType "NodePort") (not (empty $port.nodePort))) }}
      nodePort: {{ $port.nodePort }}
        {{ end }}
        {{- if (not (empty $port.appProtocol)) }}
      appProtocol: {{ $port.appProtocol }}
        {{ end }}
      {{- end -}}
  {{- with (merge
    ($object.extraSelectorLabels | default dict)
    (dict "app.kubernetes.io/component" $object.controller)
    (include "base.lib.metadata.selectorLabels" $rootContext | fromYaml)
  ) }}
  selector: {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
