{{- /*
Applies the `enabled` field of the probes (livenessProbe, readinessProbe, startupProbe) of the containers: a probe with
`enabled: false` is removed, which is how a container opts out of a probe set by `defaults.container`. The field is stripped
from the other probes. A probe with no handler (`httpGet`, `tcpSocket`, `exec` or `grpc`) is removed too: the defaults only
set the timings, so a container that sets no handler has no probe (the API rejects a probe without handler, and any probe on
an initContainer that is not a sidecar). The probes are the schema paths found by the build in `probePaths`.

Two shorthands save repeating the handler:
- the `probe` field of a container is the handler of its probes that have none (`probe: {httpGet: {path: /health}}`): a
  probe the container does not set at all (no default either) is created from it. The field is stripped.
- the `port` of an `httpGet`, `tcpSocket` or `grpc` defaults to the port of the container: its only one, or the one named
  `http`, else the render fails. The name of the port is used, except for `grpc` that needs the number.
*/}}
{{- define "base.resources.mutations.probes" }}
  {{- $work := .work }}
  {{- $probePaths := .probePaths | default list }}
  {{- if and $work.enabled $probePaths }}
    {{- /* the containers are the parents of the probes */}}
    {{- $containerPaths := list }}
    {{- range $probePath := $probePaths }}
      {{- if contains "." $probePath }}
        {{- $containerPaths = append $containerPaths (regexReplaceAll "\\.[^.]+$" $probePath "") }}
      {{- end }}
    {{- end }}
    {{- $resource := $work.resource | default dict }}
    {{- $converted := include "base.lib.probesValue" (dict
          "value" $resource
          "path" ""
          "probePaths" $probePaths
          "containerPaths" (uniq $containerPaths)
          "where" (printf "resources.%s.%s" .name .id)) | fromYaml }}
    {{- $work = set $work "resource" $converted.value }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* Prints `true` when the probe has a handler. */}}
{{- define "base.lib.probesHasHandler" }}
  {{- if or (hasKey . "httpGet") (hasKey . "tcpSocket") (hasKey . "exec") (hasKey . "grpc") }}true{{- end }}
{{- end }}

{{- /* Walks the value (path segments are only added by map keys, like in the schema) and handles the maps found at a
probePaths entry (the probes) and at a containerPaths entry (the containers). Returns {value: ...}, with `removed: true` for a
disabled probe: the parent drops the key. */}}
{{- define "base.lib.probesValue" }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- $probePaths := .probePaths }}
  {{- $containerPaths := .containerPaths }}
  {{- $where := .where }}
  {{- $removed := false }}
  {{- if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $probePaths) }}
      {{- if and (hasKey $value "enabled") (not (include "base.lib.isEnabled" (dict "enabled" (get $value "enabled")) | trim)) }}
        {{- $removed = true }}
      {{- else if not (include "base.lib.probesHasHandler" $value | trim) }}
        {{- $removed = true }}
      {{- else }}
        {{- $value = omit $value "enabled" }}
      {{- end }}
    {{- else }}
      {{- if and (ne $path "") (has $path $containerPaths) }}
        {{- $value = include "base.lib.probesContainer" (dict "container" $value "where" $where) | fromYaml }}
      {{- end }}
      {{- $out := dict }}
      {{- range $key, $v := $value }}
        {{- $childPath := $key }}
        {{- if ne $path "" }}
          {{- $childPath = printf "%s.%s" $path $key }}
        {{- end }}
        {{- $converted := include "base.lib.probesValue" (dict "value" $v "path" $childPath "probePaths" $probePaths "containerPaths" $containerPaths "where" $where) | fromYaml }}
        {{- if not $converted.removed }}
          {{- $out = set $out $key $converted.value }}
        {{- end }}
      {{- end }}
      {{- $value = $out }}
    {{- end }}
  {{- else if kindIs "slice" $value }}
    {{- $out := list }}
    {{- range $item := $value }}
      {{- $converted := include "base.lib.probesValue" (dict "value" $item "path" $path "probePaths" $probePaths "containerPaths" $containerPaths "where" $where) | fromYaml }}
      {{- $out = append $out $converted.value }}
    {{- end }}
    {{- $value = $out }}
  {{- end }}
  {{- dict "value" $value "removed" $removed | toYaml }}
{{- end }}

{{- /* Gives the handler of the `probe` field to the probes of a container that have none, creating the ones it does not
set, and fills the port of the handlers. Strips the `probe` field. */}}
{{- define "base.lib.probesContainer" }}
  {{- $container := .container }}
  {{- $where := printf "%s: container %q" .where (get $container "name" | toString) }}
  {{- $shared := get $container "probe" }}
  {{- $container = omit $container "probe" }}
  {{- range $name := (list "livenessProbe" "readinessProbe" "startupProbe") }}
    {{- $probe := get $container $name }}
    {{- if and $shared (not (hasKey $container $name)) }}
      {{- $probe = dict }}
    {{- end }}
    {{- if kindIs "map" $probe }}
      {{- if and $shared (not (include "base.lib.probesHasHandler" $probe | trim)) }}
        {{- $probe = merge (deepCopy $probe) (deepCopy $shared) }}
      {{- end }}
      {{- $probe = include "base.lib.probesPort" (dict "probe" $probe "container" $container "where" (printf "%s: %s" $where $name)) | fromYaml }}
      {{- $container = set $container $name $probe }}
    {{- end }}
  {{- end }}
  {{- toYaml $container }}
{{- end }}

{{- /* Sets the port of the handlers of a probe that have none, to the port of the container. */}}
{{- define "base.lib.probesPort" }}
  {{- $probe := deepCopy .probe }}
  {{- range $handler := (list "httpGet" "tcpSocket" "grpc") }}
    {{- $action := get $probe $handler }}
    {{- if and (kindIs "map" $action) (not (hasKey $action "port")) }}
      {{- $port := include "base.lib.probesContainerPort" (dict "container" $.container "number" (eq $handler "grpc") "where" (printf "%s: %s" $.where $handler)) | fromYaml }}
      {{- $probe = set $probe $handler (set $action "port" $port.port) }}
    {{- end }}
  {{- end }}
  {{- toYaml $probe }}
{{- end }}

{{- /* The port of the container a probe defaults to: its only port, or the one named `http`. Returns {port: ...}: the name of
the port, or its number with `number`. */}}
{{- define "base.lib.probesContainerPort" }}
  {{- $ports := get .container "ports" }}
  {{- $names := list }}
  {{- if kindIs "map" $ports }}
    {{- $names = keys $ports | sortAlpha }}
  {{- end }}
  {{- $name := "" }}
  {{- if eq (len $names) 1 }}
    {{- $name = first $names }}
  {{- else if has "http" $names }}
    {{- $name = "http" }}
  {{- else if not $names }}
    {{- fail (printf "%s has no port and the container has no ports: set the port" .where) }}
  {{- else }}
    {{- fail (printf "%s has no port and the container has several ports (%s): set the port, or name one of them http" .where (join ", " $names)) }}
  {{- end }}
  {{- $port := $name }}
  {{- if .number }}
    {{- $port = get (get $ports $name | default dict) "containerPort" }}
    {{- if not $port }}
      {{- fail (printf "%s has no port, and the port %q of the container has no containerPort" .where $name) }}
    {{- end }}
  {{- end }}
  {{- dict "port" $port | toYaml }}
{{- end }}
