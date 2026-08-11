{{/*
Probes used by the container.
*/}}
{{- define "base.resources.containers.fields.probes" -}}
  {{- $ctx := .ctx -}}
  {{- $rootContext := $ctx.rootContext -}}
  {{- $controllerObject := $ctx.controllerObject -}}
  {{- $containerObject := $ctx.containerObject -}}

  {{- /* Default to empty dict */ -}}
  {{- $enabledProbes := dict -}}

  {{- range $probeName, $probeValues := $containerObject.probes -}}
    {{- if include "base.lib.utils.isEnabled" $probeValues -}}
      {{- $probeDefinition := dict -}}

      {{- if $probeValues.custom -}}
        {{- $parsedProbeSpec := tpl ($probeValues.spec | toYaml) $rootContext -}}
        {{- $probeDefinition = $parsedProbeSpec | fromYaml -}}
      {{- else -}}
        {{- $primaryService := include "base.resources.services.primaryForController" (dict "rootContext" $rootContext "controllerIdentifier" $controllerObject.identifier) | fromYaml -}}
        {{- $primaryServiceDefaultPort := dict -}}
        {{- if $primaryService -}}
          {{- $primaryServiceDefaultPort = include "base.resources.services.primaryPort" (dict "rootContext" $rootContext "serviceObject" $primaryService) | fromYaml -}}
        {{- end -}}
        {{- if $primaryServiceDefaultPort -}}
          {{- $probeType := "" -}}
          {{- if eq $probeValues.type "AUTO" -}}
            {{- $probeType = $primaryServiceDefaultPort.protocol -}}
          {{- else -}}
            {{- $probeType = $probeValues.type | default "TCP" -}}
          {{- end -}}

          {{- $_ := set $probeDefinition "initialDelaySeconds" $probeValues.spec.initialDelaySeconds -}}
          {{- $_ := set $probeDefinition "failureThreshold" $probeValues.spec.failureThreshold -}}
          {{- $_ := set $probeDefinition "timeoutSeconds" $probeValues.spec.timeoutSeconds -}}
          {{- $_ := set $probeDefinition "periodSeconds" $probeValues.spec.periodSeconds -}}
          {{- $_ := set $probeDefinition "successThreshold" $probeValues.spec.successThreshold -}}

          {{- $probeHeader := "" -}}
          {{- if or ( eq $probeType "HTTPS" ) ( eq $probeType "HTTP" ) -}}
            {{- $probeHeader = "httpGet" -}}

            {{- $_ := set $probeDefinition $probeHeader (
              dict
                "path" $probeValues.path
                "scheme" $probeType
              )
            -}}
          {{- else }}
            {{- $probeHeader = "tcpSocket" -}}
            {{- $_ := set $probeDefinition $probeHeader dict -}}
          {{- end -}}

          {{- if $probeValues.port -}}
            {{- if kindIs "float64" $probeValues.port -}}
              {{- $_ := set (index $probeDefinition $probeHeader) "port" $probeValues.port -}}
            {{- else if kindIs "string" $probeValues.port -}}
              {{- $_ := set (index $probeDefinition $probeHeader) "port" (tpl ( $probeValues.port | toString ) $rootContext) -}}
            {{- end -}}
          {{- else if $primaryServiceDefaultPort.targetPort -}}
            {{- $_ := set (index $probeDefinition $probeHeader) "port" $primaryServiceDefaultPort.targetPort -}}
          {{- else -}}
            {{- $_ := set (index $probeDefinition $probeHeader) "port" ($primaryServiceDefaultPort.port | toString | atoi ) -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}

      {{- if $probeDefinition -}}
        {{- $_ := set $enabledProbes (printf "%sProbe" $probeName) $probeDefinition -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- with $enabledProbes -}}
    {{- . | toYaml -}}
  {{- end -}}
{{- end -}}
