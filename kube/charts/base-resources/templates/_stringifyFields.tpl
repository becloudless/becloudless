{{/*
Serializes any non-string values under a set of top-level fields (e.g.
"data" for configMaps) into YAML strings, so a resource's own value for one
of those fields may be given as either a plain string or an arbitrary
YAML/JSON node (object, array, number, bool) - matching what the upstream
k8s type actually expects (e.g. ConfigMap.data is a map[string]string). See
resources.yaml's per-kind `stringifyFields` option (the build tool's
transform.StringifyFields relaxes the field's generated JSON schema
accordingly, see generate/transform/stringify_fields.go).

Params (passed as a dict):
  resource        - the resource's (already defaulted/merged/templated) values
  stringifyFields - list of top-level field names to process

Returns the resource's values (as YAML, like base-resources.renderResource's
"resource" input) with every declared field's non-string entries replaced by
their YAML string representation. Callers should pipe the result through
`fromYaml` to get back a dict, e.g.:

  {{- $resource = include "base-resources.stringifyFields" (dict "resource" $resource "stringifyFields" $stringifyFields) | fromYaml }}
*/}}
{{- define "base-resources.stringifyFields" }}
  {{- $resource := .resource | default dict }}
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
  {{- $resource | toYaml }}
{{- end }}
