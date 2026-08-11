{{- define "base.features.istio" -}}  

{{- if include "base.lib.utils.isEnabled" $.Values.istio.resourceValidation }}
resources:
  sidecars:
  {{- range $key, $sidecar := $.Values.resources.sidecars }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

  virtualServices:
  {{- range $key, $virtualService := $.Values.resources.virtualServices }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

  destinationRules:
  {{- range $key, $destinationRule := $.Values.resources.destinationRules }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

  serviceEntries:
  {{- range $key, $serviceEntry := $.Values.resources.serviceEntries }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

  authorizationPolicies:
  {{- range $key, $authorizationPolicy := $.Values.resources.authorizationPolicies }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

  telemetries:
  {{- range $key, $telemetry := $.Values.resources.telemetries }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

  envoyFilters:
  {{- range $key, $envoyfilter := $.Values.resources.envoyFilters }}
    {{$key}}:
      labels:
        istio.io/tag: {{ $.Values.istio.resourceValidation.revisionTag }}
  {{- end }}

{{- end }}
{{- end }}
