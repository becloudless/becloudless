{{- define "base-resources.mutations.enabled" }}
  {{- include "base-resources.lib.isEnabled" .resource }}
{{- end }}
