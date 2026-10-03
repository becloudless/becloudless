{{- define "base.renderResourceKind" }}
  {{- $context := merge dict . }}
  {{- $resourcesAll := $context.rootContext.Values.resources | default dict }}

  {{- range $id, $resource := (get $resourcesAll $context.name | default dict) }}
    {{- include "base.renderResource" (merge (dict "id" $id "resource" ($resource | default dict)) $context) }}
  {{- end }}
{{- end }}
