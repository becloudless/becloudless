{{- define "base-resources.mutations.content" }}
  {{- $work := .work }}
  {{- $object := $work.object | default dict }}
  {{- $contentIsSpec := true }}
  {{- if hasKey . "contentIsSpec" }}
    {{- $contentIsSpec = .contentIsSpec }}
  {{- end }}
  {{- $resource := $work.resource | default dict }}

  {{- $cleaned := omit $resource "nameOverride" "fullNameOverride" "namespace" "labels" "annotations" }}
  {{- if $contentIsSpec }}
    {{- $object = set $object "spec" $cleaned }}
  {{- else }}
    {{- range $key, $value := $cleaned }}
      {{- $object = set $object $key $value }}
    {{- end }}
  {{- end }}
  {{- $work = set $work "object" $object }}
  {{- toYaml $work }}
{{- end }}
