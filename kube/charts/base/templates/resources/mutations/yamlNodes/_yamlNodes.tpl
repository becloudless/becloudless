{{- /*
Serializes to a YAML string the nodes (maps, lists) given for the string fields of `yamlNodes` (see YamlNodes), the
strings are kept as they are: the patch of a kustomize post renderer of a HelmRelease can be written as a YAML node
instead of a YAML document in a string. It runs once the maps are converted back to arrays (`mapsToArrays`) and before the
content is wrapped (`content`), so the paths are the ones of the schema: only the keys of the maps add a path segment, the
items of the lists keep the path of the list.
*/}}
{{- define "base.resources.mutations.yamlNodes" }}
  {{- $work := .work }}
  {{- $fields := .yamlNodes | default list }}
  {{- if and $work.enabled $fields }}
    {{- $converted := include "base.lib.yamlNodesValue" (dict "value" ($work.resource | default dict) "path" "" "fields" $fields) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* Returns {value: ...}: the value, with the nodes of the fields serialized to a string. */}}
{{- define "base.lib.yamlNodesValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $fields := .fields }}
  {{- if kindIs "map" $value }}
    {{- $out := dict }}
    {{- range $key, $v := $value }}
      {{- $childPath := $key }}
      {{- if ne $path "" }}
        {{- $childPath = printf "%s.%s" $path $key }}
      {{- end }}
      {{- if and (has $childPath $fields) (or (kindIs "map" $v) (kindIs "slice" $v)) }}
        {{- $out = set $out $key (toYaml $v | trimSuffix "\n") }}
      {{- else }}
        {{- $converted := include "base.lib.yamlNodesValue" (dict "value" $v "path" $childPath "fields" $fields) | fromYaml }}
        {{- $out = set $out $key $converted.value }}
      {{- end }}
    {{- end }}
    {{- $value = $out }}
  {{- else if kindIs "slice" $value }}
    {{- $out := list }}
    {{- range $item := $value }}
      {{- $converted := include "base.lib.yamlNodesValue" (dict "value" $item "path" $path "fields" $fields) | fromYaml }}
      {{- $out = append $out $converted.value }}
    {{- end }}
    {{- $value = $out }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}
