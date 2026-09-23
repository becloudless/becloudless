{{/*
Computes the final metadata.name for a resource instance.

Params (passed as a dict):
  rootContext - the root Helm context (usually `$`)
  id          - the resource's key under .Values.resources.<kind>
  resource    - the resource's (already defaulted/merged) values, which may
                contain `nameOverride` (replaces just the id part) and/or
                `fullNameOverride` (replaces the entire computed name)

Returns "<Release.Name>-<id>", unless overridden by `nameOverride` (replaces
the id part) or `fullNameOverride` (replaces the whole name). If the
(possibly overridden) id part is "main", the name is just "<Release.Name>"
with no suffix.
*/}}
{{- define "base-resources.computeName" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
  {{- if $resource.fullNameOverride }}
    {{- $resource.fullNameOverride }}
  {{- else }}
    {{- $resourceName := $id }}
    {{- if $resource.nameOverride }}
      {{- $resourceName = $resource.nameOverride }}
    {{- end }}
    {{- if eq $resourceName "main" }}
      {{- $rootContext.Release.Name }}
    {{- else }}
      {{- printf "%s-%s" $rootContext.Release.Name $resourceName }}
    {{- end }}
  {{- end }}
{{- end }}
