{{- /*
Applies the `enabled` field of the probes (livenessProbe, readinessProbe, startupProbe) of the containers: a probe with
`enabled: false` is removed, which is how a container opts out of a probe set by `defaults.container`. The field is stripped
from the other probes. A probe with no handler (`httpGet`, `tcpSocket`, `exec` or `grpc`) is removed too: the defaults only
set the timings, so a container that sets no handler has no probe (the API rejects a probe without handler, and any probe on
an initContainer that is not a sidecar). The probes are the schema paths found by the build in `probePaths`.
*/}}
{{- define "base.resources.mutations.probes" }}
  {{- $work := .work }}
  {{- $probePaths := .probePaths | default list }}
  {{- if and $work.enabled $probePaths }}
    {{- $resource := $work.resource | default dict }}
    {{- $converted := include "base.lib.probesValue" (dict "value" $resource "path" "" "probePaths" $probePaths) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* Walks the value (path segments are only added by map keys, like in the schema) and handles the maps found at a
probePaths entry. Returns {value: ...}, with `removed: true` for a disabled probe: the parent drops the key. */}}
{{- define "base.lib.probesValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $probePaths := .probePaths }}
  {{- $removed := false }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $probePaths) }}
      {{- if and (hasKey $value "enabled") (not (include "base.lib.isEnabled" (dict "enabled" (get $value "enabled")) | trim)) }}
        {{- $removed = true }}
      {{- else if not (or (hasKey $value "httpGet") (hasKey $value "tcpSocket") (hasKey $value "exec") (hasKey $value "grpc")) }}
        {{- $removed = true }}
      {{- else }}
        {{- $value = omit $value "enabled" }}
      {{- end }}
    {{- else }}
      {{- $out := dict }}
      {{- range $key, $v := $value }}
        {{- $childPath := $key }}
        {{- if ne $path "" }}
          {{- $childPath = printf "%s.%s" $path $key }}
        {{- end }}
        {{- $converted := include "base.lib.probesValue" (dict "value" $v "path" $childPath "probePaths" $probePaths) | fromYaml }}
        {{- if not $converted.removed }}
          {{- $out = set $out $key $converted.value }}
        {{- end }}
      {{- end }}
      {{- $value = $out }}
    {{- end }}
  {{- else if kindIs "slice" $value }}
    {{- $out := list }}
    {{- range $item := $value }}
      {{- $converted := include "base.lib.probesValue" (dict "value" $item "path" $path "probePaths" $probePaths) | fromYaml }}
      {{- $out = append $out $converted.value }}
    {{- end }}
    {{- $value = $out }}
  {{- end }}
  {{- dict "value" $value "removed" $removed | toYaml }}
{{- end }}
