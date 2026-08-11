{{- define "base.resources.destinationRules.istioEgressServiceToDestinationService" -}}
{{- default .  | replace "." "-"  | replace "*" "wildcard" }}
{{- end }}
