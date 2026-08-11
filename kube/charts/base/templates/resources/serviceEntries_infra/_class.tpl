
{{- define "istio.serviceEntry.ports" -}}
  {{- range $name, $values := . }}
- number: {{ $values.number }}
  name: {{ $name }}
  protocol: {{ $values.protocol }}
  {{- end -}}
{{- end }}

{{- define "base.resources.serviceEntries.class" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- $labels := merge
    ($object.labels | default dict)
    (include "base.lib.metadata.allLabels" (dict "rootContext" $rootContext "identifier" $object.identifier ) | fromYaml)
  -}}
  {{- $annotations := merge
    ($object.annotations | default dict)
    (include "base.lib.metadata.globalAnnotations" $rootContext | fromYaml)
  -}}

---
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: {{ $object.name }}
  {{- with $labels }}
  labels: {{- toYaml . | nindent 4 -}}
  {{- end }}
  {{- with $annotations }}
  annotations: {{- toYaml . | nindent 4 -}}
  {{- end }}

spec:
  hosts:
    {{- toYaml $object.hosts | nindent 4 }}
  {{- with $object.addresses }}
  addresses:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.exportTo }}
  exportTo:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.resolution }}
  resolution: {{ . }}
  {{- end }}
  {{- with $object.ports }}
  ports:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.subjectAltNames }}
  subjectAltNames:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $object.location }}
  location: {{ . }}
  {{- end }}
{{- end -}}
