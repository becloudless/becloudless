{{- /*
Drops the `rollingUpdate` of the strategy of a deployment that uses the `Recreate` type: the API rejects both, and the
`rollingUpdate` is the one of `defaults.resources.deployments.strategy`, merged by the defaults mutation (which runs before).
*/}}
{{- define "base.resources.mutations.recreateStrategy" }}
  {{- $work := .work }}
  {{- if and $work.enabled (eq .name "deployments") }}
    {{- $strategy := get ($work.resource | default dict) "strategy" }}
    {{- if and (kindIs "map" $strategy) (eq (get $strategy "type") "Recreate") }}
      {{- $_ := unset $strategy "rollingUpdate" }}
    {{- end }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}
