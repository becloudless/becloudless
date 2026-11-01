{{- /*
Sets the fields of the items of the id-keyed maps (the arrays converted by the build, see `arrayPaths`) given by
`itemFields` (see ItemFields), when the item does not set them: `keyField` gets the key of the item, `defaults` the
given values. An item given as `{}` or empty is a map with these fields. It runs before the check of the required fields
and the conversion of the maps back to arrays, which needs the keys: the field `port` of the ports of a Cilium policy is
required, and given by the key.
*/}}
{{- define "base.resources.mutations.itemFields" }}
  {{- $work := .work }}
  {{- $itemFields := .itemFields | default dict }}
  {{- if and $work.enabled $itemFields }}
    {{- $resource := $work.resource | default dict }}
    {{- $converted := include "base.lib.itemFieldsValue" (dict "value" $resource "path" "" "arrayPaths" (.arrayPaths | default list) "itemFields" $itemFields) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* Like `base.lib.mapsToArraysValue`: the path segments are only added by map keys, an item of an id-keyed map keeps the
path of the map. Returns {value: ...}. */}}
{{- define "base.lib.itemFieldsValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $arrayPaths := .arrayPaths }}
  {{- $itemFields := .itemFields }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $arrayPaths) }}
      {{- $config := get $itemFields $path }}
      {{- $out := dict }}
      {{- range $itemKey, $item := $value }}
        {{- if and $config (kindIs "invalid" $item) }}
          {{- $item = dict }}
        {{- end }}
        {{- if kindIs "map" $item }}
          {{- if and $config $config.keyField (not (hasKey $item $config.keyField)) }}
            {{- $item = set $item $config.keyField $itemKey }}
          {{- end }}
          {{- range $field, $default := ($config | default dict).defaults }}
            {{- if not (hasKey $item $field) }}
              {{- $item = set $item $field $default }}
            {{- end }}
          {{- end }}
          {{- $item = (include "base.lib.itemFieldsObject" (dict "value" $item "path" $path "arrayPaths" $arrayPaths "itemFields" $itemFields) | fromYaml).value }}
        {{- end }}
        {{- $out = set $out $itemKey $item }}
      {{- end }}
      {{- $value = $out }}
    {{- else }}
      {{- $value = (include "base.lib.itemFieldsObject" (dict "value" $value "path" $path "arrayPaths" $arrayPaths "itemFields" $itemFields) | fromYaml).value }}
    {{- end }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}

{{- /* Iterates the keys of a map, each adding a path segment. */}}
{{- define "base.lib.itemFieldsObject" }}
  {{- $path := .path }}
  {{- $out := dict }}
  {{- range $key, $v := .value }}
    {{- $childPath := $key }}
    {{- if ne $path "" }}
      {{- $childPath = printf "%s.%s" $path $key }}
    {{- end }}
    {{- $converted := include "base.lib.itemFieldsValue" (dict "value" $v "path" $childPath "arrayPaths" $.arrayPaths "itemFields" $.itemFields) | fromYaml }}
    {{- $out = set $out $key $converted.value }}
  {{- end }}
  {{- dict "value" $out | toYaml }}
{{- end }}
