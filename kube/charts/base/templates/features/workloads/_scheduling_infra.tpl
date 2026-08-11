{{- define "base.workloads.scheduling" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- if include "base.lib.utils.isEnabled" (dig "scheduling" dict $workload ) -}}
resources:
  controllers:
    {{$workloadId}}:
      pod:
      {{- if include "base.lib.utils.isEnabled" $workload.scheduling.podSpreadingForHA }}
        affinity:
          {{- if include "base.lib.utils.isEnabled" $workload.scheduling.podSpreadingForHA }}
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: app
                        operator: In
                        values:
                        - {{ $rootContext.Release.Name }}
                      - key: app.kubernetes.io/component
                        operator: In
                        values:
                        - {{ $workloadId }}
                  topologyKey: kubernetes.io/hostname
                weight: 50
          {{- end }}
      {{- end }}

      {{- if include "base.lib.utils.isEnabled" $workload.scheduling.podSpreadingForHA }}
        topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: "topology.kubernetes.io/zone"
          whenUnsatisfiable: ScheduleAnyway     # toleration zone issue
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: {{ $workloadId }}
              {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 14 }}
        - maxSkew: {{ $workload.scheduling.podSpreadingForHA.hostnameMaxSkew }}
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule      # clusterAutoscaler will start a new node if needed
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: {{ $workloadId }}
              {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 14 }}
      {{- end }}

{{- end -}}
{{- end }}
