{{- define "base.resources.mutations.mapsToPorts" }}
  {{- $work := .work }}
  {{- $portPaths := .portPaths | default list }}
  {{- if and $work.enabled $portPaths }}
    {{- $resource := $work.resource | default dict }}
    {{- $converted := include "base.lib.mapsToPortsValue" (dict "value" $resource "path" "" "portPaths" $portPaths) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{/* Converts the map found at a portPaths entry into a list of ports (key -> name, value -> the other fields, sorted by name), recursing into maps and lists (path segments are only added by map keys, like in the schema). Wraps the result in {value: ...} since `fromYaml` needs a map to parse into. */}}
{{- define "base.lib.mapsToPortsValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $portPaths := .portPaths }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $portPaths) }}
      {{- $list := list }}
      {{- range $name := (keys $value | sortAlpha) }}
        {{- $port := deepCopy (get $value $name | default dict) }}
        {{- $list = append $list (set $port "name" $name) }}
      {{- end }}
      {{- $value = $list }}
    {{- else }}
      {{- $out := dict }}
      {{- range $key, $v := $value }}
        {{- $childPath := $key }}
        {{- if ne $path "" }}
          {{- $childPath = printf "%s.%s" $path $key }}
        {{- end }}
        {{- $converted := include "base.lib.mapsToPortsValue" (dict "value" $v "path" $childPath "portPaths" $portPaths) | fromYaml }}
        {{- $out = set $out $key $converted.value }}
      {{- end }}
      {{- $value = $out }}
    {{- end }}
  {{- else if and (kindIs "slice" $value) (not (has $path $portPaths)) }}
    {{- $out := list }}
    {{- range $item := $value }}
      {{- $converted := include "base.lib.mapsToPortsValue" (dict "value" $item "path" $path "portPaths" $portPaths) | fromYaml }}
      {{- $out = append $out $converted.value }}
    {{- end }}
    {{- $value = $out }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}
