{{- /*
The container definition included in the Pod.
*/ -}}
{{- define "base.resources.containers.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerObject := .controllerObject -}}
  {{- $containerObject := .containerObject -}}
  {{- $ctx := dict "rootContext" $rootContext "controllerObject" $controllerObject "containerObject" $containerObject -}}

{{/* Inference service do not like when we set the name of the model */}}
{{- if ne $controllerObject.type "InferenceService" }}
name: {{ include "base.resources.containers.fields.name" (dict "ctx" $ctx) | trim }}
{{- end }}
image: {{ include "base.resources.containers.fields.image" (dict "ctx" $ctx) | trim }}
imagePullPolicy: IfNotPresent
  {{- with (include "base.resources.containers.fields.command" (dict "ctx" $ctx) | trim) }}
command: {{ . | trim | nindent 2 }}
  {{- end -}}
  {{- with (include "base.resources.containers.fields.args" (dict "ctx" $ctx) | trim) }}
args: {{ . | trim | nindent 2 }}
  {{- end -}}
  {{- with $containerObject.workingDir }}
workingDir: {{ . | trim }}
  {{- end -}}
  {{- with $containerObject.securityContext }}
securityContext: {{ toYaml . | trim | nindent 2 }}
  {{- end -}}
  {{- with $containerObject.lifecycle }}
lifecycle: {{ toYaml . | trim | nindent 2 }}
  {{- end -}}
  {{- with $containerObject.terminationMessagePath }}
terminationMessagePath: {{ . | trim }}
  {{- end -}}
  {{- with $containerObject.terminationMessagePolicy }}
terminationMessagePolicy: {{ . | trim }}
  {{- end -}}
  {{- with (include "base.resources.containers.fields.env" (dict "ctx" $ctx) | trim) }}
env: {{ . | trim | nindent 2 }}
  {{- end -}}
  {{- with (include "base.resources.containers.fields.envFrom" (dict "ctx" $ctx) | trim) }}
envFrom: {{ . | trim | nindent 2 }}
  {{- end -}}
  {{- with $containerObject.ports }}
ports: {{ toYaml . | trim | nindent 2 }}
  {{- end -}}
  {{- with (include "base.resources.containers.fields.probes" (dict "ctx" $ctx) | trim) }}
    {{- . | trim | nindent 0 -}}
  {{- end -}}
  {{- with $containerObject.resources }}
resources: {{ toYaml . | trim | nindent 2 }}
  {{- end -}}
  {{- with (include "base.resources.containers.fields.volumeMounts" (dict "ctx" $ctx) | trim) }}
volumeMounts: {{ . | trim | nindent 2 }}
  {{- end -}}
{{- end -}}
