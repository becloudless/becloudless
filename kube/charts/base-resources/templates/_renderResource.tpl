{{- define "base-resources.renderResource" }}
  {{- $params := dict "rootContext" .rootContext "id" .id "apiVersion" .apiVersion "kind" .kind "contentIsSpec" .contentIsSpec "resource" (.resource | default dict) }}

  {{- $object := dict }}
  {{- range $mutation := (list "base-resources.mutations.apiVersionKind" "base-resources.mutations.metadata" "base-resources.mutations.content") }}
    {{- $object = include $mutation (merge (dict "object" $object) $params) | fromYaml }}
  {{- end }}
---
{{ toYaml $object }}
{{- end }}
