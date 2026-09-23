{{/*
Computes the full `metadata:` block for a resource instance: name, namespace,
labels and annotations, from a fixed set of well-known fields on the
resource's (already defaulted/merged) values.

Params (passed as a dict):
  rootContext - the root Helm context (usually `$`)
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
metadata:
  name: {{ $name }}
  namespace: {{ $namespace }}
  {{- if $resource.labels }}
  labels:
    {{- toYaml $resource.labels | nindent 4 }}
  {{- end }}
  {{- if $resource.annotations }}
  annotations:
    {{- toYaml $resource.annotations | nindent 4 }}
  {{- end }}
{{- end }}
