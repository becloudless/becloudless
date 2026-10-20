{{- /*
Fails when a field required by the schema of the kind is missing in the resource, at any depth. The resource is
validated once the defaults are merged, which the validation of the values schema cannot do.
`.required` is the tree generated from the schema (see Required.go): `required` the fields of the object, `properties` the
trees of its named properties, `each` the tree of the entries of its map or list.
*/}}
{{- define "base.resources.mutations.required" }}
  {{- $work := .work }}
  {{- if $work.enabled }}
    {{- include "base.lib.requiredCheck" (dict
          "value" ($work.resource | default dict)
          "tree" (.required | default dict)
          "path" (printf "resources.%s.%s" .name .id)) }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- define "base.lib.requiredCheck" }}
  {{- $value := .value }}
  {{- $tree := .tree }}
  {{- $path := .path }}
  {{- $properties := $tree.properties | default dict }}
  {{- if kindIs "map" $value }}
    {{- range $field := ($tree.required | default list) }}
      {{- if not (hasKey $value $field) }}
        {{- fail (printf "%s: %q is required" $path $field) }}
      {{- end }}
    {{- end }}
    {{- range $name, $subtree := $properties }}
      {{- if hasKey $value $name }}
        {{- include "base.lib.requiredCheck" (dict "value" (get $value $name) "tree" $subtree "path" (printf "%s.%s" $path $name)) }}
      {{- end }}
    {{- end }}
    {{- if $tree.each }}
      {{- range $key, $entry := $value }}
        {{- if not (hasKey $properties $key) }}
          {{- include "base.lib.requiredCheck" (dict "value" $entry "tree" $tree.each "path" (printf "%s.%s" $path $key)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- else if and (kindIs "slice" $value) $tree.each }}
    {{- range $i, $entry := $value }}
      {{- include "base.lib.requiredCheck" (dict "value" $entry "tree" $tree.each "path" (printf "%s[%d]" $path $i)) }}
    {{- end }}
  {{- end }}
{{- end }}
