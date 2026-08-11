{{/*
Validate VirtualService values
*/}}
{{- define "base.resources.sidecars.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $object := .object -}}

  {{- range $i, $v := dig "egress" dict $object -}}
    {{- if not (dig "hosts" list $v) -}}
      {{- fail (printf "hosts is required on sidecar.egress. (sidecar: %s, egress: %d)" $object.identifier $i) -}}
    {{- end -}}
  {{- end -}}

  {{- range $i, $v := dig "ingress" dict $object -}}
    {{- if not (dig "port" nil $v) -}}
      {{- fail (printf "port is required on sidecar.ingress. (sidecar: %s, ingress: %d)" $object.identifier $i) -}}
    {{- end -}}
  {{- end -}}

{{- end -}}
