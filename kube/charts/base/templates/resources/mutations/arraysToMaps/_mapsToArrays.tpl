{{- define "base.resources.mutations.mapsToArrays" }}
  {{- $work := .work }}
  {{- $arrayPaths := .arrayPaths | default list }}
  {{- if $work.enabled }}
    {{- $resource := $work.resource | default dict }}
    {{- $reversed := include "base.lib.mapsToArraysValue" (dict "value" $resource "path" "" "arrayPaths" $arrayPaths) | fromYaml }}
    {{- $work = set $work "resource" $reversed.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{/* Converts value at path back into an array if path is a recorded arrayPaths entry, recursing into children either way. Wraps the result in {value: ...} since the result can be a list, map, or scalar, and `fromYaml` needs a map to parse into. */}}
{{- define "base.lib.mapsToArraysValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $arrayPaths := .arrayPaths }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $arrayPaths) }}
      {{- $list := list }}
      {{- range $itemKey := (keys $value | sortAlpha) }}
        {{- $item := include "base.lib.mapsToArraysObject" (dict "value" (get $value $itemKey) "path" $path "arrayPaths" $arrayPaths) | fromYaml }}
        {{- $list = append $list $item.value }}
      {{- end }}
      {{- $value = $list }}
    {{- else }}
      {{- $value = (include "base.lib.mapsToArraysObject" (dict "value" $value "path" $path "arrayPaths" $arrayPaths) | fromYaml).value }}
    {{- end }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}

{{/* Iterates a map's own keys, each adding a path segment, and reverses each value. */}}
{{- define "base.lib.mapsToArraysObject" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $arrayPaths := .arrayPaths }}
  {{- $out := dict }}
  {{- if kindIs "map" $value }}
    {{- range $key, $v := $value }}
      {{- $childPath := $key }}
      {{- if ne $path "" }}
        {{- $childPath = printf "%s.%s" $path $key }}
      {{- end }}
      {{- $reversed := include "base.lib.mapsToArraysValue" (dict "value" $v "path" $childPath "arrayPaths" $arrayPaths) | fromYaml }}
      {{- $out = set $out $key $reversed.value }}
    {{- end }}
  {{- else }}
    {{- $out = $value }}
  {{- end }}
  {{- dict "value" $out | toYaml }}
{{- end }}
