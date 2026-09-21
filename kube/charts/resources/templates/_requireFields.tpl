{{/*
Validates that a resource's (already defaulted/merged) values contain every
field listed as required by the kind's upstream k8s JSON schema.

This exists because .Values.resources.<kind>.<id> and
.Values.defaults.resources.<kind> intentionally share the exact same JSON
schema (see schema/resources/<kind>.json), which never declares a top-level
"required": a defaults.resources entry is only a partial overlay and
shouldn't be forced to satisfy "required" on its own. Instead, "required" is
enforced here, at render time, against the MERGED resource (resource merged
with defaults.resources.<kind>).

Params (passed as a dict):
  name     - the resource kind's name (e.g. "horizontalPodAutoscalers"), used
             in the error message
  id       - the resource's key under .Values.resources.<kind>, used in the
             error message
  resource - the resource's (already defaulted/merged) values
  required - list of field names that must be present on resource
*/}}
{{- define "resources.generic.requireFields" }}
  {{- $name := .name }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
  {{- range $field := (.required | default list) }}
    {{- if not (hasKey $resource $field) }}
      {{- fail (printf "resources.%s.%s: %q is required" $name $id $field) }}
    {{- end }}
  {{- end }}
{{- end }}
