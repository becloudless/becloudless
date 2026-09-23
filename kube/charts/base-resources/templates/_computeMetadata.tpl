{{/*
Computes the full `metadata:` block for a resource instance: name, namespace,
labels and annotations, from a fixed set of well-known fields on the
resource's (already defaulted/merged) values, additionally layering in
global label/annotation defaults from .Values.defaults.metadata (applied
across every resource of every kind), below the resource's own
(already per-kind-defaulted) labels/annotations in precedence.

Params (passed as a dict):
  rootContext - the root Helm context (usually `$`); also used to read
                .Values.defaults.metadata.{labels,annotations}
  id          - the resource's key under .Values.resources.<kind>
  resource    - the resource's (already defaulted/merged) values, which may
                contain:
                  nameOverride     - replaces just the id part of the name
                  fullNameOverride - replaces the entire computed name
                  namespace        - metadata.namespace (defaults to the
                                     release namespace)
                  labels           - metadata.labels
                  annotations      - metadata.annotations

Returns a `metadata:` YAML block. The caller is responsible for stripping
`nameOverride`, `fullNameOverride`, `namespace`, `labels` and `annotations`
from the resource's values before rendering the rest of the manifest, so
they aren't duplicated into `spec:` (or the root, when contentIsSpec: false).
*/}}
{{- define "base-resources.generic.computeMetadata" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}

  {{- $name := include "base-resources.generic.computeName" (dict "rootContext" $rootContext "id" $id "resource" $resource) }}
  {{- $namespace := $resource.namespace | default $rootContext.Release.Namespace }}

  {{- $defaultsAll := $rootContext.Values.defaults | default dict }}
  {{- $globalMetadataAll := $defaultsAll.metadata | default dict }}
  {{- $globalMetadataAll = tpl (toYaml $globalMetadataAll) $rootContext | fromYaml }}
  {{- $labels := merge ($resource.labels | default dict) ($globalMetadataAll.labels | default dict) }}
  {{- $annotations := merge ($resource.annotations | default dict) ($globalMetadataAll.annotations | default dict) }}
metadata:
  name: {{ $name }}
  namespace: {{ $namespace }}
  {{- if $labels }}
  labels:
    {{- toYaml $labels | nindent 4 }}
  {{- end }}
  {{- if $annotations }}
  annotations:
    {{- toYaml $annotations | nindent 4 }}
  {{- end }}
{{- end }}
