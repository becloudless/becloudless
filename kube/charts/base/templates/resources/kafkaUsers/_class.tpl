{{/*
This template serves as the blueprint for the KafkaUsers objects that are created
within the common library.
*/}}
{{- define "base.resources.kafkaUsers.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $labels := merge
    (dict "app.kubernetes.io/component" $object.identifier)
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: {{ $object.name }}
  namespace: {{ $object.namespace }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}
spec:
  authentication:
    type: tls
  {{- with $object.authorization.acls }}
  authorization:
    type: simple
    acls:
      {{- range . }}
      - resource:
          type: {{ .resource.type }}
          {{- if has .resource.type (list "topic" "group" "transactionalId") }}
          name: {{ .resource.name }}
          patternType: {{ default "literal" .resource.patternType }}
          {{- end }}
        {{- with .operations }}
        operations: {{- . | toYaml | nindent 10 }}
        {{- end }}
      {{- end }}
  {{- end }}
  {{- with $object.replicateToNamespacesAnnotation }}
  template:
    secret:
      metadata:
        annotations:
          replicator.v1.mittwald.de/replicate-to: {{ . }}
  {{- end }}
---
{{- end }}
