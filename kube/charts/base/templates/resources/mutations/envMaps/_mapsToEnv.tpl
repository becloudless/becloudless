{{- define "base.resources.mutations.mapsToEnv" }}
  {{- $work := .work }}
  {{- $envPaths := .envPaths | default list }}
  {{- if and $work.enabled $envPaths }}
    {{- $resource := $work.resource | default dict }}
    {{- $converted := include "base.lib.mapsToEnvValue" (dict "value" $resource "path" "" "envPaths" $envPaths) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{/* Converts the map found at an envPaths entry into a list of EnvVar (key -> name, scalar -> value, map -> valueFrom, sorted by name), recursing into maps and lists (path segments are only added by map keys, like in the schema). Wraps the result in {value: ...} since `fromYaml` needs a map to parse into. */}}
{{- define "base.lib.mapsToEnvValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $envPaths := .envPaths }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $envPaths) }}
      {{- $list := list }}
      {{- range $name := (keys $value | sortAlpha) }}
        {{- $v := get $value $name }}
        {{- if kindIs "map" $v }}
          {{- $list = append $list (dict "name" $name "valueFrom" $v) }}
        {{- else }}
          {{- $str := toString $v }}
          {{- if and (kindIs "float64" $v) (eq $v (floor $v)) }}
            {{- $str = toString (int64 $v) }}
          {{- end }}
          {{- $list = append $list (dict "name" $name "value" $str) }}
        {{- end }}
      {{- end }}
      {{- $value = $list }}
    {{- else }}
      {{- $out := dict }}
      {{- range $key, $v := $value }}
        {{- $childPath := $key }}
        {{- if ne $path "" }}
          {{- $childPath = printf "%s.%s" $path $key }}
        {{- end }}
        {{- $converted := include "base.lib.mapsToEnvValue" (dict "value" $v "path" $childPath "envPaths" $envPaths) | fromYaml }}
        {{- $out = set $out $key $converted.value }}
      {{- end }}
      {{- $value = $out }}
    {{- end }}
  {{- else if and (kindIs "slice" $value) (not (has $path $envPaths)) }}
    {{- $out := list }}
    {{- range $item := $value }}
      {{- $converted := include "base.lib.mapsToEnvValue" (dict "value" $item "path" $path "envPaths" $envPaths) | fromYaml }}
      {{- $out = append $out $converted.value }}
    {{- end }}
    {{- $value = $out }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}
