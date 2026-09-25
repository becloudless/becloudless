{{- define "base-resources.mutations.stringifyFields" }}
  {{- $work := .work }}
  {{- $resource := $work.resource | default dict }}
  {{- $fields := .stringifyFields | default list }}
  {{- range $field := $fields }}
    {{- if hasKey $resource $field }}
      {{- $stringified := dict }}
      {{- range $k, $v := (get $resource $field) }}
        {{- if kindIs "string" $v }}
          {{- $stringified = set $stringified $k $v }}
        {{- else }}
          {{- $stringified = set $stringified $k (toYaml $v | trimSuffix "\n") }}
        {{- end }}
      {{- end }}
      {{- $resource = set $resource $field $stringified }}
    {{- end }}
  {{- end }}
  {{- $work = set $work "resource" $resource }}
  {{- toYaml $work }}
{{- end }}
