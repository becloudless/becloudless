{{- /*
Replaces the references (`ref:<id>`) of the fields of `refs` (see Refs) by what they point to: another resource of the release,
or of a sibling release (the HelmReleases of a parent chart, see `refsIndex`).

  - `ref:<id>`: the resource with this id, of the kinds the field accepts (`name: ref:web` for a backend of a route, the service `web`);
  - `ref:<kind>/<id>`: the same, of a kind only (`ref:deployments/web`), needed when several kinds have this id;
  - `ref:<kind>/<id>@<release>` (or `ref:<id>@<release>`): in a sibling release, by the id of its HelmRelease, needed when several
    siblings have this id.

The resources are looked up in this release first, then in all the siblings, merged: the kind and the release are not part of the
reference unless it is ambiguous (the lookup then fails and says so).

The reference is replaced by the projection of the field (`as`, see `base.lib.refs.project`): the name of the resource, the
selector of its pods, ... Whatever is not a `ref:` string is left as is. A reference that points to nothing (no such resource,
disabled, unknown release) fails, a reference never is a name that is silently kept. A map of entries accepts a list of references
too (`parentRefs: [ref:a, ref:b]`), the id of each is the key of its entry. An array kept as is (not in `arrayPaths`) has each of its
`ref:` items replaced in place (`dependsOn: [ref:db, {name: other, namespace: elsewhere}]`).

Runs after the defaults (the templates are rendered) and before `itemFields`/`required`, the paths are the ones of the values
(see `base.lib.listShorthandsValue`): an id-keyed map (arrays, env) keeps the path of its entries.
*/}}
{{- define "base.resources.mutations.refs" }}
  {{- $work := .work }}
  {{- $refs := .refs | default dict }}
  {{- if and $work.enabled $refs }}
    {{- $resource := $work.resource | default dict }}
    {{- if contains "ref:" (toYaml $resource) }}
      {{- $selfNamespace := "" }}
      {{- if not .clusterScoped }}
        {{- $selfNamespace = include "base.lib.refs.namespace" (dict "resource" $resource "values" .rootContext.Values "releaseNamespace" .rootContext.Release.Namespace "rootContext" .rootContext) }}
      {{- end }}
      {{- $context := dict
            "rootContext" .rootContext
            "refs" $refs
            "idKeyed" (concat (.arrayPaths | default list) (.envPaths | default list))
            "selfNamespace" $selfNamespace
            "where" (printf "resources.%s.%s" .name .id) }}
      {{- $converted := include "base.lib.refs.value" (dict "context" $context "value" $resource "path" "") | fromYaml }}
      {{- $work = set $work "resource" $converted.value }}
    {{- end }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* The namespace of a resource: its own, else the default of the values, else the one of the release. The default of the
values is a template (`{{ .Release.Namespace }}`) rendered with the root context, or when there is none (a sibling release, which
is not rendered here) the release namespace. */}}
{{- define "base.lib.refs.namespace" }}
  {{- $resource := .resource | default dict }}
  {{- $values := .values | default dict }}
  {{- $metadata := ($values.defaults | default dict).metadata | default dict }}
  {{- $namespace := $resource.namespace | default $metadata.namespace | default .releaseNamespace }}
  {{- if contains "{{" $namespace }}
    {{- if .rootContext }}
      {{- $namespace = tpl $namespace .rootContext }}
    {{- else }}
      {{- $namespace = .releaseNamespace }}
    {{- end }}
  {{- end }}
  {{- $namespace }}
{{- end }}

{{- /* What a reference can use of a resource: its name, its namespace, the labels that select its pods (workloads) and the name of
its Secret (the certificates and the external secrets name it, the other secrets have the name of the resource). Needs the
release name and namespace (it is the one of the sibling for its resources), the values of the release (`prefixNamesWithRelease`,
`defaults`) and the kind, id and description of the resource. Returns {name, namespace[, labels][, secretName]}: the labels are only
there for the workloads, and the name of the Secret when it is not the name of the resource. */}}
{{- define "base.lib.refs.entry" }}
  {{- $resource := .resource | default dict }}
  {{- $values := .values | default dict }}
  {{- $computeContext := dict "Release" (dict "Name" .releaseName) "Values" (dict "prefixNamesWithRelease" ($values.prefixNamesWithRelease | default false)) }}
  {{- /* a templated name (see `tpl`) is only known by the resource itself: it cannot be referenced by its name, but its pods can still be selected */}}
  {{- $name := "" }}
  {{- if not (or (contains "{{" ($resource.fullNameOverride | default "")) (contains "{{" ($resource.nameOverride | default ""))) }}
    {{- $name = include "base.lib.computeResourceName" (dict "rootContext" $computeContext "id" .id "resource" $resource) }}
  {{- end }}
  {{- $namespace := include "base.lib.refs.namespace" (dict "resource" $resource "values" $values "releaseNamespace" .releaseNamespace "rootContext" .rootContext) }}

  {{- $labels := dict }}
  {{- if has .kind (list "deployments" "statefulSets" "daemonSets" "jobs" "cronJobs") }}
    {{- $podTemplate := $resource.template | default dict }}
    {{- if eq .kind "cronJobs" }}
      {{- $podTemplate = (($resource.jobTemplate | default dict).spec | default dict).template | default dict }}
    {{- end }}
    {{- $podLabels := ($podTemplate.metadata | default dict).labels | default dict }}
    {{- /* the standard labels (see `standardLabels`), unless the pod template sets its own */}}
    {{- $labels = dict
          "app.kubernetes.io/instance" (get $podLabels "app.kubernetes.io/instance" | default .releaseName)
          "app.kubernetes.io/component" (get $podLabels "app.kubernetes.io/component" | default .id) }}
  {{- end }}

  {{- $secretName := $name }}
  {{- if eq .kind "certManagerCertificates" }}
    {{- $secretName = $resource.secretName | default $name }}
  {{- else if eq .kind "externalSecrets" }}
    {{- $secretName = ($resource.target | default dict).name | default $name }}
  {{- end }}
  {{- $entry := dict "name" $name "namespace" $namespace }}
  {{- if $labels }}
    {{- $entry = set $entry "labels" $labels }}
  {{- end }}
  {{- if ne $secretName $name }}
    {{- $entry = set $entry "secretName" $secretName }}
  {{- end }}
  {{- toYaml $entry }}
{{- end }}

{{- /* What the reference becomes, by the projection (`as`) of the field:
  - `name`: the name of the resource;
  - `secretName`: the name of its Secret;
  - `gatewayRef`: the parent of a route, `{group, kind, name}` (and the namespace when it is not the one of the resource);
  - `roleRef`: the role of a binding, `{apiGroup, kind, name}`;
  - `serviceAccountSubject`: the subject of a binding, `{kind: ServiceAccount, name, namespace}`;
  - `podSelector`: the selector of its pods, `{matchLabels}` (with the namespace when it is not the one of the resource, or of a
    resource that has none);
  - `helmReleaseRef`: `{name}` of a HelmRelease (and the namespace when it is not the one of the resource);
  - `secretStoreRef`: the store of an external secret, `{name, kind}` (SecretStore or ClusterSecretStore).
Returns {value: ...}. */}}
{{- define "base.lib.refs.project" }}
  {{- $entry := .entry }}
  {{- $value := "" }}
  {{- if and (ne .as "podSelector") (not $entry.name) }}
    {{- fail (printf "%s: the name of the %s is templated, it cannot be referenced" .where .kind) }}
  {{- end }}
  {{- if eq .as "name" }}
    {{- $value = $entry.name }}
  {{- else if eq .as "secretName" }}
    {{- $value = $entry.secretName | default $entry.name }}
  {{- else if eq .as "gatewayRef" }}
    {{- $kind := get (dict "listenerSets" "ListenerSet" "gateways" "Gateway") .kind }}
    {{- if not $kind }}
      {{- fail (printf "%s: %s cannot be the parent of a route" .where .kind) }}
    {{- end }}
    {{- $value = dict "group" "gateway.networking.k8s.io" "kind" $kind "name" $entry.name }}
    {{- if ne $entry.namespace .selfNamespace }}
      {{- $value = set $value "namespace" $entry.namespace }}
    {{- end }}
  {{- else if eq .as "podSelector" }}
    {{- if not $entry.labels }}
      {{- fail (printf "%s: %s has no pods to select" .where .kind) }}
    {{- end }}
    {{- $labels := deepCopy $entry.labels }}
    {{- if ne $entry.namespace .selfNamespace }}
      {{- $labels = set $labels "k8s:io.kubernetes.pod.namespace" $entry.namespace }}
    {{- end }}
    {{- $value = dict "matchLabels" $labels }}
  {{- else if eq .as "roleRef" }}
    {{- $kind := get (dict "roles" "Role" "clusterRoles" "ClusterRole") .kind }}
    {{- if not $kind }}
      {{- fail (printf "%s: %s cannot be the role of a binding" .where .kind) }}
    {{- end }}
    {{- $value = dict "apiGroup" "rbac.authorization.k8s.io" "kind" $kind "name" $entry.name }}
  {{- else if eq .as "serviceAccountSubject" }}
    {{- $value = dict "kind" "ServiceAccount" "name" $entry.name "namespace" $entry.namespace }}
  {{- else if eq .as "helmReleaseRef" }}
    {{- $value = dict "name" $entry.name }}
    {{- if ne $entry.namespace .selfNamespace }}
      {{- $value = set $value "namespace" $entry.namespace }}
    {{- end }}
  {{- else if eq .as "secretStoreRef" }}
    {{- $kind := get (dict "secretStores" "SecretStore" "clusterSecretStores" "ClusterSecretStore") .kind }}
    {{- if not $kind }}
      {{- fail (printf "%s: %s cannot be the store of an external secret" .where .kind) }}
    {{- end }}
    {{- $value = dict "name" $entry.name "kind" $kind }}
  {{- else }}
    {{- fail (printf "%s: unknown projection %q" .where .as) }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}

{{- /* The kind, the id and the release (empty: not named) of a reference, as {kind, id, release}. The kind is the only one the field
accepts when it is not given, else it is empty: the resource is looked up in all the kinds the field accepts. */}}
{{- define "base.lib.refs.parse" }}
  {{- $reference := .reference }}
  {{- $body := trimPrefix "ref:" $reference }}
  {{- $release := "" }}
  {{- if contains "@" $body }}
    {{- $parts := splitList "@" $body }}
    {{- if ne (len $parts) 2 }}
      {{- fail (printf "%s: %q is not a reference (ref:<kind>/<id>@<release>)" .where $reference) }}
    {{- end }}
    {{- $body = first $parts }}
    {{- $release = last $parts }}
  {{- end }}
  {{- $kind := "" }}
  {{- $id := $body }}
  {{- if contains "/" $body }}
    {{- $parts := splitList "/" $body }}
    {{- if ne (len $parts) 2 }}
      {{- fail (printf "%s: %q is not a reference (ref:<kind>/<id>@<release>)" .where $reference) }}
    {{- end }}
    {{- $kind = first $parts }}
    {{- $id = last $parts }}
    {{- if not (has $kind .kinds) }}
      {{- fail (printf "%s: %q is a %s, only %s can be referenced here" .where $reference $kind (join ", " .kinds)) }}
    {{- end }}
  {{- else if eq (len .kinds) 1 }}
    {{- $kind = first .kinds }}
  {{- end }}
  {{- if not $id }}
    {{- fail (printf "%s: %q has no id" .where $reference) }}
  {{- end }}
  {{- dict "kind" $kind "id" $id "release" $release | toYaml }}
{{- end }}

{{- /* Finds what a reference points to, and replaces it by its projection. The candidates are the resources with the id, of the
kind (or of any kind the field accepts), of this release, else of the siblings (all of them, or the one named by `@<release>`). It
fails when there is none, or several. Returns {value: ...}. */}}
{{- define "base.lib.refs.resolve" }}
  {{- $context := .context }}
  {{- $rootContext := $context.rootContext }}
  {{- $spec := .spec }}
  {{- $where := printf "%s: %s" $context.where .path }}
  {{- $target := include "base.lib.refs.parse" (dict "reference" .reference "kinds" $spec.kinds "where" $where) | fromYaml }}
  {{- $kinds := $spec.kinds }}
  {{- if $target.kind }}
    {{- $kinds = list $target.kind }}
  {{- end }}
  {{- $resources := $rootContext.Values.resources | default dict }}

  {{- /* the resources of this release win over the ones of the siblings */}}
  {{- $candidates := list }}
  {{- $disabled := list }}
  {{- $known := dict }}
  {{- if not $target.release }}
    {{- range $kind := $kinds }}
      {{- $items := get $resources $kind | default dict }}
      {{- $known = merge $known $items }}
      {{- if hasKey $items $target.id }}
        {{- if include "base.lib.isEnabled" (get $items $target.id) | trim }}
          {{- $candidates = append $candidates (dict "kind" $kind "release" "") }}
        {{- else }}
          {{- $disabled = append $disabled $kind }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- /* the HelmReleases of this release (the resources of a parent chart), merged with the ones its parent shares (`refs`) */}}
  {{- $siblings := dict }}
  {{- if not $candidates }}
    {{- if not (hasKey $context "siblings") }}
      {{- $shared := $rootContext.Values.refs | default dict }}
      {{- $own := include "base.lib.refs.releases" (dict "rootContext" $rootContext) | fromYaml }}
      {{- $_ := set $context "siblings" (merge (dict) $own $shared) }}
    {{- end }}
    {{- $siblings = $context.siblings }}
    {{- $releases := keys $siblings | sortAlpha }}
    {{- if $target.release }}
      {{- if not (hasKey $siblings $target.release) }}
        {{- fail (printf "%s: %q: no sibling release %q with resources%s" $where .reference $target.release (include "base.lib.refs.known" $siblings)) }}
      {{- end }}
      {{- $releases = list $target.release }}
    {{- end }}
    {{- range $release := $releases }}
      {{- range $kind := $kinds }}
        {{- $items := get (get $siblings $release | default dict) $kind | default dict }}
        {{- if hasKey $items $target.id }}
          {{- $candidates = append $candidates (dict "kind" $kind "release" $release) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- if not $candidates }}
    {{- if $disabled }}
      {{- fail (printf "%s: %q: the %s %q is disabled" $where .reference (join "/" $disabled) $target.id) }}
    {{- else if $target.release }}
      {{- fail (printf "%s: %q: the release %q has no enabled %s %q" $where .reference $target.release (join "/" $kinds) $target.id) }}
    {{- else }}
      {{- fail (printf "%s: %q: no %s %q in this release or its siblings%s" $where .reference (join "/" $kinds) $target.id (include "base.lib.refs.known" $known)) }}
    {{- end }}
  {{- end }}
  {{- if gt (len $candidates) 1 }}
    {{- $names := list }}
    {{- range $candidate := $candidates }}
      {{- $names = append $names (ternary $candidate.kind (printf "%s@%s" $candidate.kind $candidate.release) (eq $candidate.release "")) }}
    {{- end }}
    {{- fail (printf "%s: %q: several resources have this id (%s), choose with `ref:<kind>/<id>@<release>`" $where .reference (join ", " $names)) }}
  {{- end }}

  {{- $candidate := first $candidates }}
  {{- $entry := dict }}
  {{- if $candidate.release }}
    {{- $entry = get (get (get $siblings $candidate.release) $candidate.kind) $target.id }}
  {{- else }}
    {{- $entry = include "base.lib.refs.entry" (dict "kind" $candidate.kind "id" $target.id "resource" (get (get $resources $candidate.kind) $target.id) "releaseName" $rootContext.Release.Name "releaseNamespace" $rootContext.Release.Namespace "values" $rootContext.Values "rootContext" $rootContext) | fromYaml }}
  {{- end }}

  {{- include "base.lib.refs.project" (dict "entry" $entry "as" $spec.as "kind" $candidate.kind "selfNamespace" $context.selfNamespace "where" $where) }}
{{- end }}

{{- /* A value at a path. A string at the path of a field is a reference to resolve. A list of references at the path of a map of
entries is the map of their projections, by id. A map is visited: the entries of a map keyed by id (see the arrays, `idKeyed`)
keep its path, the keys of the other maps add a segment. Returns {value: ...}. */}}
{{- define "base.lib.refs.value" }}
  {{- $context := .context }}
  {{- $value := .value }}
  {{- $path := .path }}
  {{- if kindIs "string" $value }}
    {{- if and (hasPrefix "ref:" $value) (hasKey $context.refs $path) }}
      {{- $value = (include "base.lib.refs.resolve" (dict "context" $context "reference" $value "spec" (get $context.refs $path) "path" $path) | fromYaml).value }}
    {{- end }}
  {{- else if kindIs "slice" $value }}
    {{- if and $value (hasKey $context.refs $path) (not (has $path $context.idKeyed)) }}
      {{- /* an array kept as is: its items are references, or objects */}}
      {{- $items := list }}
      {{- range $entry := $value }}
        {{- $items = append $items (include "base.lib.refs.value" (dict "context" $context "value" $entry "path" $path) | fromYaml).value }}
      {{- end }}
      {{- $value = $items }}
    {{- else if and $value (hasKey $context.refs $path) }}
      {{- $references := true }}
      {{- range $entry := $value }}
        {{- if not (and (kindIs "string" $entry) (hasPrefix "ref:" $entry)) }}
          {{- $references = false }}
        {{- end }}
      {{- end }}
      {{- if $references }}
        {{- $spec := get $context.refs $path }}
        {{- $entries := dict }}
        {{- range $reference := $value }}
          {{- $target := include "base.lib.refs.parse" (dict "reference" $reference "kinds" $spec.kinds "where" (printf "%s: %s" $context.where $path)) | fromYaml }}
          {{- if hasKey $entries $target.id }}
            {{- fail (printf "%s: %s: two references have the id %q, use the map (`<key>: ref:...`) to name them" $context.where $path $target.id) }}
          {{- end }}
          {{- $entries = set $entries $target.id (include "base.lib.refs.resolve" (dict "context" $context "reference" $reference "spec" $spec "path" $path) | fromYaml).value }}
        {{- end }}
        {{- $value = $entries }}
      {{- end }}
    {{- end }}
  {{- else if kindIs "map" $value }}
    {{- if and (ne $path "") (has $path $context.idKeyed) }}
      {{- $out := dict }}
      {{- range $key, $entry := $value }}
        {{- if kindIs "string" $entry }}
          {{- if and (hasPrefix "ref:" $entry) (hasKey $context.refs $path) }}
            {{- $entry = (include "base.lib.refs.resolve" (dict "context" $context "reference" $entry "spec" (get $context.refs $path) "path" $path) | fromYaml).value }}
          {{- end }}
        {{- else if kindIs "map" $entry }}
          {{- $entry = (include "base.lib.refs.object" (dict "context" $context "value" $entry "path" $path) | fromYaml).value }}
        {{- end }}
        {{- $out = set $out $key $entry }}
      {{- end }}
      {{- $value = $out }}
    {{- else }}
      {{- $value = (include "base.lib.refs.object" (dict "context" $context "value" $value "path" $path)| fromYaml).value }}
    {{- end }}
  {{- end }}
  {{- dict "value" $value | toYaml }}
{{- end }}

{{- /* The values of the keys of a map, each adding a segment to the path. Returns {value: ...}. */}}
{{- define "base.lib.refs.object" }}
  {{- $path := .path }}
  {{- $out := dict }}
  {{- range $key, $entry := .value }}
    {{- $childPath := $key }}
    {{- if ne $path "" }}
      {{- $childPath = printf "%s.%s" $path $key }}
    {{- end }}
    {{- $out = set $out $key (include "base.lib.refs.value" (dict "context" $.context "value" $entry "path" $childPath) | fromYaml).value }}
  {{- end }}
  {{- dict "value" $out | toYaml }}
{{- end }}

{{- /* What a lookup that missed can say: the ids that exist, if any. */}}
{{- define "base.lib.refs.known" }}
  {{- if . }}
    {{- printf " (known: %s)" (keys . | sortAlpha | join ", ") }}
  {{- end }}
{{- end }}
