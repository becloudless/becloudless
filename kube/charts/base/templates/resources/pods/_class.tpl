{{- /*
The pod definition included in the controller.
*/ -}}
{{- define "base.resources.pods.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerObject := .controllerObject -}}
  {{- $doNotRenderContainers := .doNotRenderContainers -}}
  {{- $ctx := dict "rootContext" $rootContext "controllerObject" $controllerObject -}}

enableServiceLinks: {{ $controllerObject.pod.enableServiceLinks }}
  {{- with ($controllerObject.pod.serviceAccountName) }}
serviceAccountName: {{ $controllerObject.pod.serviceAccountName }}
  {{- end }}
automountServiceAccountToken: {{ $controllerObject.pod.automountServiceAccountToken }}
  {{- with ($controllerObject.pod.priorityClassName) }}
priorityClassName: {{ . | trim }}
  {{- end }}
  {{- with ($controllerObject.pod.runtimeClassName) }}
runtimeClassName: {{ . | trim }}
  {{- end }}
  {{- with ($controllerObject.pod.schedulerName) }}
schedulerName: {{ . | trim }}
  {{- end }}
  {{- with ($controllerObject.pod.securityContext) }}
securityContext: {{- . | toYaml | nindent 2 }}
  {{- end }}
  {{- with ($controllerObject.pod.hostname) }}
hostname: {{ . | trim }}
  {{- end }}
  {{- if hasKey $controllerObject.pod "hostIPC" }}
hostIPC: {{ $controllerObject.pod.hostIPC }}
  {{- end }}
  {{- if hasKey $controllerObject.pod "hostNetwork" }}
hostNetwork: {{ $controllerObject.pod.hostNetwork }}
  {{- end }}
  {{- if hasKey $controllerObject.pod "hostPID" }}
hostPID: {{ $controllerObject.pod.hostPID }}
  {{- end }}
dnsPolicy: {{ include "base.resources.pods.fields.dnsPolicy" (dict "ctx" $ctx) | trim }}
  {{- with $controllerObject.pod.dnsConfig }}
dnsConfig: {{- . | toYaml | nindent 2 }}
  {{- end }}
  {{- with $controllerObject.pod.hostAliases }}
hostAliases: {{ . | toYaml | nindent 2 }}
  {{- end }}
  {{- with $controllerObject.pod.imagePullSecrets }}
imagePullSecrets: {{ . | toYaml | nindent 2 }}
  {{- end }}
  {{- with $controllerObject.pod.terminationGracePeriodSeconds }}
terminationGracePeriodSeconds: {{ . | trim }}
  {{- end }}
  {{- with $controllerObject.pod.restartPolicy }}
restartPolicy: {{ . | trim }}
  {{- end }}
  {{- with $controllerObject.pod.nodeSelector }}
nodeSelector: {{- . | toYaml | nindent 2 }}
  {{- end }}
  {{- with $controllerObject.pod.affinity }}
affinity: {{- . | toYaml | nindent 2 }}
  {{- end }}
  {{- with $controllerObject.pod.topologySpreadConstraints }}
topologySpreadConstraints: {{- . | toYaml | nindent 2 }}
  {{- end }}
  {{- with $controllerObject.pod.tolerations }}
tolerations: {{- . | toYaml | nindent 2 }}
  {{- end }}
{{- if not $doNotRenderContainers }}
  {{- with (include "base.resources.pods.fields.initContainers" (dict "ctx" $ctx) | trim) }}
initContainers: {{- . | nindent 2 }}
  {{- end -}}
  {{- with (include "base.resources.pods.fields.containers" (dict "ctx" $ctx) | trim) }}
containers: {{- . | nindent 2 }}
  {{- end }}
{{- end }}
  {{- with (include "base.resources.pods.fields.volumes" (dict "ctx" $ctx) | trim) }}
volumes: {{- . | nindent 2 }}
  {{- end }}
{{- end -}}
