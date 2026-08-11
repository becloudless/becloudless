{{- define "base.workloads.resources" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}

{{- if or
  (include "base.lib.utils.isEnabled" (dig "serviceAccount" dict $workload))
  (include "base.lib.utils.isEnabled" (dig "pdb" dict $workload))
  (include "base.lib.utils.isEnabled" (dig "service" dict $workload))
}}
resources:
  {{- if include "base.lib.utils.isEnabled" (dig "serviceAccount" dict $workload) }}
  serviceAccounts:
    {{$workloadId}}:
      {{ $workload.serviceAccount | toYaml | nindent 6 }}
  {{- end }}

  {{- if include "base.lib.utils.isEnabled" (dig "pdb" dict $workload) }}
  podDisruptionBudgets:
    {{$workloadId}}:
      controller: {{$workloadId}}
      {{ $workload.pdb | toYaml | nindent 6 }}
  {{- end }}

  {{- if include "base.lib.utils.isEnabled" (dig "ingress" dict $workload) }}
  ingresses:
    {{$workloadId}}:
      {{ $workload.ingress | toYaml | nindent 6 }}
  {{- end }}

  {{- if include "base.lib.utils.isEnabled" (dig "service" dict $workload) }}
  services:
    {{$workloadId}}:
      controller: {{$workloadId}}
      {{$workload.service | toYaml | nindent 6}}
  controllers:
    {{$workloadId}}:
      containers:
        main:
          ports:
          {{- range $portName, $port := $workload.service.ports -}}
            {{- $tmpPort := dict "containerPort" (default $port.port $port.targetPort) "name" $portName -}}
            {{- if $port.protocol -}}
              {{- $_ := set $tmpPort "protocol" $port.protocol -}}
            {{- end -}}
            {{- list $tmpPort | toYaml | nindent 12 }}
          {{- end -}}
  {{- end }}
{{- end }}

{{- end -}}
