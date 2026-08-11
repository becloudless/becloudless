{{- define "base.workloads.istio" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- if include "base.lib.utils.isEnabled" (dig "istio" dict $workload ) -}}
resources:
  sidecars:
    {{$workloadId}}:
      workloadLabels:
        app.kubernetes.io/component: {{ $workloadId }}
        {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 8 }}

      blockUndefinedOutbound: {{$workload.istio.blockUndefinedDependencies }}
      egress:
        - hosts:
            {{- range $egressListener, $params := $workload.istio.dependencies }}
              {{-  if contains "/" $egressListener }}
                {{- printf "- %s" $egressListener | nindent 12 }}
              {{- else }}
                {{- printf "- \"*/%s\"" $egressListener | nindent 12 }}
              {{- end }}
            {{- end }}
{{ else }}
resources:
  controllers:
    {{$workloadId}}:
      pod:
        labels:
          sidecar.istio.io/inject: "false"
{{- end }}
{{- end -}}
