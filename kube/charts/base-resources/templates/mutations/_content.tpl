{{- define "base-resources.mutations.content" }}
  {{- $object := .object | default dict }}
  {{- $contentIsSpec := .contentIsSpec }}
  {{- $resource := .resource | default dict }}

  {{- $cleaned := omit $resource "nameOverride" "fullNameOverride" "namespace" "labels" "annotations" "enabled" }}
  {{- if $contentIsSpec }}
    {{- $object = set $object "spec" $cleaned }}
  {{- else }}
    {{- range $key, $value := $cleaned }}
      {{- $object = set $object $key $value }}
    {{- end }}
  {{- end }}
  {{- toYaml $object }}
{{- end }}
