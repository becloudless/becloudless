{{- define "base.workloads.istioResources" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- /*
IMPORTANT:
When we set only one annotation, istio removes its own default value for all the 3 others values.
And it can be dangerous: no memory-request if user only sets the cpu-request for example :S
Thus our choice here: we *always* define the 4 values (using helm-default if needed).
*/}}
{{- if include "base.lib.utils.isEnabled" (dig "istio" dict $workload ) -}}
resources:
  controllers:
    {{$workloadId}}:
      pod:
        annotations:
          sidecar.istio.io/proxyCPU: {{ $workload.istio.proxyResources.requests.cpu | quote }}
          sidecar.istio.io/proxyCPULimit: {{ $workload.istio.proxyResources.limits.cpu | quote }}
          sidecar.istio.io/proxyMemory: {{ $workload.istio.proxyResources.requests.memory | quote }}
          sidecar.istio.io/proxyMemoryLimit: {{ $workload.istio.proxyResources.limits.memory | quote }}
{{- end -}}
{{- end }}
