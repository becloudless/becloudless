{{- define "base.workloads.istioPubliclyExposed" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- if include "base.lib.utils.isEnabled" (dig "istio" "publiclyExposed" dict $workload ) -}}
  {{- $gateway := default "restricted" $workload.istio.publiclyExposed.gateway -}}
  {{- $gateways := (list "restricted" "public") -}}
  {{- if not (has $gateway $gateways) }}
    {{- fail (printf "istio.publiclyExposed.gateway must be one of %v (workload: %s)" $gateways $workloadId) }}
  {{- end }}
  {{- $primaryService := include "base.resources.services.primaryForController" (dict "rootContext" $rootContext "controllerIdentifier" $workloadId) | fromYaml -}}
resources:
  virtualServices:
    {{$workloadId}}:
      gateways:
        - istio-system/istio-ingressgateway-{{ $gateway }}
      hosts:
        {{- $workload.istio.publiclyExposed.hosts | toYaml | nindent 8 }}
      http:
      {{- if $workload.istio.publiclyExposed.http }}
        {{- $workload.istio.publiclyExposed.http | toYaml | nindent 8 }}
      {{- else }}
        - route:
            - destination:
                host: {{ $primaryService.name }}
      {{- end }}
      exportTo:
        - istio-system
{{- end -}}
{{- end }}
