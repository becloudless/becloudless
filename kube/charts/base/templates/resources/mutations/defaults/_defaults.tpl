{{- /*
Merges the defaults in a resource, from the strongest to the weakest:
  - the resource itself;
  - `defaults.resources.<kind>`;
  - `defaults.pod`, for the pod spec of the kinds that have a pod template (deployments, statefulSets, daemonSets, jobs, cronJobs);
  - `defaults.container`, for each container and initContainer of these pod specs.

The fields set by the resource win, even when their value is `false`, `0` or empty: sprig `merge` is not used, it takes them for unset
and replaces them by the default (`readOnlyRootFilesystem: false` could not opt out of a default `true`).
*/}}
{{- define "base.resources.mutations.defaults" }}
  {{- $rootContext := .rootContext }}
  {{- $work := .work }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $defaultsResourcesAll := $defaultsAll.resources | default dict }}
  {{- $default := get $defaultsResourcesAll .name | default dict }}

  {{- $merged := (include "base.lib.mergeDefaults" (dict "dst" ($work.resource | default dict) "src" $default) | fromYaml).value }}

  {{- $podDefault := $defaultsAll.pod | default dict }}
  {{- $containerDefault := $defaultsAll.container | default dict }}
  {{- $podSpecPaths := dict "deployments" "template.spec" "statefulSets" "template.spec" "daemonSets" "template.spec" "jobs" "template.spec" "cronJobs" "jobTemplate.spec.template.spec" }}
  {{- if and (or $podDefault $containerDefault) (hasKey $podSpecPaths .name) }}
    {{- /* the parent of the pod spec, to be able to replace the pod spec */}}
    {{- $keys := splitList "." (get $podSpecPaths .name) }}
    {{- $parent := $merged }}
    {{- range $key := initial $keys }}
      {{- if kindIs "map" $parent }}
        {{- $parent = get $parent $key }}
      {{- end }}
    {{- end }}
    {{- if kindIs "map" $parent }}
      {{- $specKey := last $keys }}
      {{- $podSpec := get $parent $specKey | default dict }}
      {{- $podSpec = (include "base.lib.mergeDefaults" (dict "dst" $podSpec "src" $podDefault) | fromYaml).value }}
      {{- /* the containers are a map keyed by id, or a list */}}
      {{- range $field := (list "containers" "initContainers") }}
        {{- $containers := get $podSpec $field }}
        {{- if kindIs "map" $containers }}
          {{- range $id, $container := $containers }}
            {{- $_ := set $containers $id (include "base.lib.mergeDefaults" (dict "dst" $container "src" $containerDefault) | fromYaml).value }}
          {{- end }}
        {{- else if kindIs "slice" $containers }}
          {{- $list := list }}
          {{- range $container := $containers }}
            {{- $list = append $list (include "base.lib.mergeDefaults" (dict "dst" $container "src" $containerDefault) | fromYaml).value }}
          {{- end }}
          {{- $_ := set $podSpec $field $list }}
        {{- end }}
      {{- end }}
      {{- $_ := set $parent $specKey $podSpec }}
    {{- end }}
  {{- end }}

  {{- $merged = tpl (toYaml $merged) $rootContext | fromYaml }}

  {{- $work = set $work "resource" $merged }}
  {{- toYaml $work }}
{{- end }}

{{- /*
Deep merge of `.src` (the defaults) under `.dst`: a key that `.dst` has wins, whatever its value, and the maps present in both are merged.
The lists are not merged, the one of `.dst` wins. Returns `{value: <merged>}`.
*/}}
{{- define "base.lib.mergeDefaults" }}
  {{- $dst := .dst }}
  {{- $src := .src }}
  {{- $out := $dst }}
  {{- if and (kindIs "map" $dst) (kindIs "map" $src) }}
    {{- $out = dict }}
    {{- range $key, $value := $src }}
      {{- $_ := set $out $key $value }}
    {{- end }}
    {{- range $key, $value := $dst }}
      {{- if hasKey $src $key }}
        {{- $value = (include "base.lib.mergeDefaults" (dict "dst" $value "src" (get $src $key)) | fromYaml).value }}
      {{- end }}
      {{- $_ := set $out $key $value }}
    {{- end }}
  {{- else if kindIs "invalid" $dst }}
    {{- $out = $src }}
  {{- end }}
  {{- dict "value" $out | toYaml }}
{{- end }}
