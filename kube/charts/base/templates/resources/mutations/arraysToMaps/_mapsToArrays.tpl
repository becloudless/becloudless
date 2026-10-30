{{- define "base.resources.mutations.mapsToArrays" }}
  {{- $work := .work }}
  {{- $arrayPaths := .arrayPaths | default list }}
  {{- $keyFields := .keyFields | default dict }}
  {{- if $work.enabled }}
    {{- $resource := $work.resource | default dict }}
    {{- $reversed := include "base.lib.mapsToArraysValue" (dict "value" $resource "path" "" "arrayPaths" $arrayPaths "keyFields" $keyFields) | fromYaml }}
    {{- $work = set $work "resource" $reversed.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{/* Converts value at path back into an array if path is a recorded arrayPaths entry, recursing into children either way. The
items of the arrays at a keyFields path get the field named by it set to their key, unless they set it. Wraps the result in
{value: ...} since the result can be a list, map, or scalar, and `fromYaml` needs a map to parse into. */}}
{{- define "base.lib.mapsToArraysValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $arrayPaths := .arrayPaths }}
  {{- $keyFields := .keyFields }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $arrayPaths) }}
      {{- $keyField := get $keyFields $path }}
      {{- $list := list }}
      {{- range $itemKey := (keys $value | sortAlpha) }}
        {{- $item := include "base.lib.mapsToArraysObject" (dict "value" (get $value $itemKey) "path" $path "arrayPaths" $arrayPaths "keyFields" $keyFields) | fromYaml }}
        {{- $itemValue := $item.value }}
        {{- if $keyField }}
          {{- $itemValue = $itemValue | default dict }}
          {{- if not (hasKey $itemValue $keyField) }}
            {{- $itemValue = set $itemValue $keyField $itemKey }}
          {{- end }}
        {{- end }}
        {{- $list = append $list $itemValue }}
      {{- end }}
      {{- $value = $list }}
    {{- else }}
      {{- $value = (include "base.lib.mapsToArraysObject" (dict "value" $value "path" $path "arrayPaths" $arrayPaths "keyFields" $keyFields) | fromYaml).value }}
    {{- end }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}

{{/* Iterates a map's own keys, each adding a path segment, and reverses each value. */}}
{{- define "base.lib.mapsToArraysObject" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $arrayPaths := .arrayPaths }}
  {{- $keyFields := .keyFields }}
  {{- $out := dict }}
  {{- if kindIs "map" $value }}
    {{- range $key, $v := $value }}
      {{- $childPath := $key }}
      {{- if ne $path "" }}
        {{- $childPath = printf "%s.%s" $path $key }}
      {{- end }}
      {{- $reversed := include "base.lib.mapsToArraysValue" (dict "value" $v "path" $childPath "arrayPaths" $arrayPaths "keyFields" $keyFields) | fromYaml }}
      {{- $out = set $out $key $reversed.value }}
    {{- end }}
  {{- else }}
    {{- $out = $value }}
  {{- end }}
  {{- dict "value" $out | toYaml }}
{{- end }}
