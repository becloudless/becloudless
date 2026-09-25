{{- define "base-resources.mutations.mergeDefaults" }}
  {{- $rootContext := .rootContext }}
  {{- $work := .work }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $defaultsResourcesAll := $defaultsAll.resources | default dict }}
  {{- $default := get $defaultsResourcesAll .name | default dict }}

  {{- $merged := merge ($work.resource | default dict) $default }}
  {{- $merged = tpl (toYaml $merged) $rootContext | fromYaml }}

  {{- $work = set $work "resource" $merged }}
  {{- toYaml $work }}
{{- end }}
