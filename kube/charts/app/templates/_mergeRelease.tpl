{{- /*
Sets a generated HelmRelease in the `fluxHelmReleases` (`.releases`) under `.name`. A release of the same name that the chart gives is
merged with it: what the chart gives wins and the maps are merged, the lists are not (the one of the chart wins) except `dependsOn`,
completed with the generated entries the chart does not have yet (same `name`, or same `ref:` string). `dependsOn` of the chart can be
a list or a map (the generated entries are added with their name as key).
*/}}
{{- define "app.lib.mergeRelease" }}
  {{- $releases := .releases }}
  {{- $generated := .generated }}
  {{- $given := get $releases .name }}
  {{- if not (kindIs "map" $given) }}
    {{- $_ := set $releases .name $generated }}
  {{- else }}
    {{- $merged := (include "base.lib.mergeDefaults" (dict "dst" (omit $given "dependsOn") "src" (omit $generated "dependsOn")) | fromYaml).value }}
    {{- $dependsOn := get $given "dependsOn" }}
    {{- $names := list }}
    {{- $entries := $dependsOn | default list }}
    {{- if kindIs "map" $dependsOn }}
      {{- $entries = values $dependsOn }}
    {{- end }}
    {{- range $entry := $entries }}
      {{- $names = append $names (include "app.lib.dependencyName" $entry) }}
    {{- end }}
    {{- range $entry := (get $generated "dependsOn" | default list) }}
      {{- $name := include "app.lib.dependencyName" $entry }}
      {{- if not (has $name $names) }}
        {{- if kindIs "map" $dependsOn }}
          {{- $_ := set $dependsOn $name $entry }}
        {{- else }}
          {{- $dependsOn = append ($dependsOn | default list) $entry }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{- if $dependsOn }}
      {{- $_ := set $merged "dependsOn" $dependsOn }}
    {{- end }}
    {{- $_ := set $releases $.name $merged }}
  {{- end }}
{{- end }}

{{- /* The name of an entry of `dependsOn`: the `name` of a map, the string itself (`ref:<release>`) otherwise. */}}
{{- define "app.lib.dependencyName" }}
  {{- if kindIs "map" . }}{{ .name }}{{ else }}{{ . }}{{ end }}
{{- end }}
