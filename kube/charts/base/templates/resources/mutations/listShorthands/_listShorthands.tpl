{{- /*
Expands the lists of scalars given for the maps of `listShorthands` (see ListShorthands): with `key: main` and
`field: ports`, `toPorts: [443, 80]` is `toPorts: {main: {ports: {"443": {}, "80": {}}}}`. A list that has maps (or lists)
in it is a real list of entries, it is left as is. It runs before `itemFields`, which gives the fields of the entries
made (the port and the protocol of the ports of a Cilium rule), and before the check of the required fields.
*/}}
{{- define "base.resources.mutations.listShorthands" }}
  {{- $work := .work }}
  {{- $listShorthands := .listShorthands | default dict }}
  {{- if and $work.enabled $listShorthands }}
    {{- $resource := $work.resource | default dict }}
    {{- $converted := include "base.lib.listShorthandsValue" (dict "value" $resource "path" "" "arrayPaths" (.arrayPaths | default list) "listShorthands" $listShorthands) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* Like `base.lib.itemFieldsValue`: the path segments are only added by map keys, an item of an id-keyed map keeps the
path of the map. Returns {value: ...}. */}}
{{- define "base.lib.listShorthandsValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $arrayPaths := .arrayPaths }}
  {{- $listShorthands := .listShorthands }}
  {{- if and (kindIs "slice" $value) (hasKey $listShorthands $path) }}
    {{- $scalars := true }}
    {{- range $entry := $value }}
      {{- if or (kindIs "map" $entry) (kindIs "slice" $entry) }}
        {{- $scalars = false }}
      {{- end }}
    {{- end }}
    {{- if $scalars }}
      {{- $shorthand := get $listShorthands $path }}
      {{- $field := dict }}
      {{- range $entry := $value }}
        {{- $field = set $field (printf "%v" $entry) dict }}
      {{- end }}
      {{- $value = dict $shorthand.key (dict $shorthand.field $field) }}
    {{- end }}
  {{- else if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $arrayPaths) }}
      {{- $out := dict }}
      {{- range $itemKey, $item := $value }}
        {{- if kindIs "map" $item }}
          {{- $item = (include "base.lib.listShorthandsObject" (dict "value" $item "path" $path "arrayPaths" $arrayPaths "listShorthands" $listShorthands) | fromYaml).value }}
        {{- end }}
        {{- $out = set $out $itemKey $item }}
      {{- end }}
      {{- $value = $out }}
    {{- else }}
      {{- $value = (include "base.lib.listShorthandsObject" (dict "value" $value "path" $path "arrayPaths" $arrayPaths "listShorthands" $listShorthands) | fromYaml).value }}
    {{- end }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}

{{- /* Iterates the keys of a map, each adding a path segment. */}}
{{- define "base.lib.listShorthandsObject" }}
  {{- $path := .path }}
  {{- $out := dict }}
  {{- range $key, $v := .value }}
    {{- $childPath := $key }}
    {{- if ne $path "" }}
      {{- $childPath = printf "%s.%s" $path $key }}
    {{- end }}
    {{- $converted := include "base.lib.listShorthandsValue" (dict "value" $v "path" $childPath "arrayPaths" $.arrayPaths "listShorthands" $.listShorthands) | fromYaml }}
    {{- $out = set $out $key $converted.value }}
  {{- end }}
  {{- dict "value" $out | toYaml }}
{{- end }}
