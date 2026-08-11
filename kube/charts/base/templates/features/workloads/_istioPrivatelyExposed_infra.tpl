{{- define "base.workloads.istioPrivatelyExposed" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- if include "base.lib.utils.isEnabled" (dig "istio" "privatelyExposed" dict $workload ) -}}
  {{- $primaryService := include "base.resources.services.primaryForController" (dict "rootContext" $rootContext "controllerIdentifier" $workloadId) | fromYaml -}}
resources:
  virtualServices:
    {{$workloadId}}:
      gateways:
        - istio-system/istio-ilbgateway
      hosts:
        {{- $workload.istio.privatelyExposed.hosts | toYaml | nindent 8 }}
      http:
      {{- if $workload.istio.privatelyExposed.http }}
        {{- $workload.istio.privatelyExposed.http | toYaml | nindent 8 }}
      {{- else }}
        - route:
            - destination:
                host: {{ $primaryService.name }}
      {{- end }}
{{- end -}}
{{- end }}
