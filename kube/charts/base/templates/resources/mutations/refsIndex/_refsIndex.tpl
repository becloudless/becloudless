{{- /*
Shares what the resources of the HelmReleases of the release are with each of them, so a resource can reference one of a sibling
release (`ref:<kind>/<id>@<release>`, see `refs`): a HelmRelease only knows its own values, the parent is the one that sees all of
them. Every HelmRelease that has resources gets, in its values, `refs`: the name, the namespace, the labels of the pods and
the name of the Secret (when it is not the name) of each enabled resource of each HelmRelease, by the id of the HelmRelease, the
kind and the id:

  refs:
    db-pre:
      stringSecrets:
        db-generated: {name: db-generated, namespace: apps}
      certManagerCertificates:
        db-tls: {name: db-tls, namespace: apps, secretName: tls-db}
    db:
      deployments:
        db: {name: db, namespace: apps, labels: {app.kubernetes.io/instance: db, app.kubernetes.io/component: db}}

The name is the one the sibling gives its resource (`prefixNamesWithRelease`, `nameOverride`, `fullNameOverride`) and the release
name is the one of Flux (`releaseName`, else `<targetNamespace>-<name>` or the name of the HelmRelease). `refs` is a value of its
own, accepted by the schema of the values and set by this mutation only. The values of the siblings are not rendered
here: a template in their namespace or their names is not known, and their `defaults.metadata.namespace` is used only when it is
not one. The parent resolves the references to its HelmReleases with the same index (see `base.lib.refs.resolve`).
*/}}
{{- define "base.resources.mutations.refsIndex" }}
  {{- $work := .work }}
  {{- if and $work.enabled (eq .name "fluxHelmReleases") }}
    {{- $resource := $work.resource | default dict }}
    {{- if kindIs "map" ($resource.values | default dict).resources }}
      {{- $index := include "base.lib.refs.releases" (dict "rootContext" .rootContext) | fromYaml }}
      {{- if $index }}
        {{- $values := set $resource.values "refs" $index }}
        {{- $work = set $work "resource" (set $resource "values" $values) }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}

{{- /* The resources of the HelmReleases of the release that have some, by the id of the HelmRelease, the kind and the id, as
`base.lib.refs.entry` describes them. */}}
{{- define "base.lib.refs.releases" }}
  {{- $rootContext := .rootContext }}
  {{- $index := dict }}
  {{- range $hrId, $hr := (get ($rootContext.Values.resources | default dict) "fluxHelmReleases" | default dict) }}
    {{- $values := ($hr | default dict).values | default dict }}
    {{- if and (kindIs "map" $values.resources) (include "base.lib.isEnabled" $hr | trim) }}
      {{- $hrName := include "base.lib.computeResourceName" (dict "rootContext" $rootContext "id" $hrId "resource" $hr) }}
      {{- $hrNamespace := include "base.lib.refs.namespace" (dict "resource" $hr "values" $rootContext.Values "releaseNamespace" $rootContext.Release.Namespace "rootContext" $rootContext) }}
      {{- $releaseName := $hr.releaseName | default $hrName }}
      {{- $releaseNamespace := $hrNamespace }}
      {{- if $hr.targetNamespace }}
        {{- $releaseNamespace = $hr.targetNamespace }}
        {{- if not $hr.releaseName }}
          {{- $releaseName = printf "%s-%s" $hr.targetNamespace $hrName }}
        {{- end }}
      {{- end }}
      {{- $kinds := dict }}
      {{- range $kind, $items := $values.resources }}
        {{- if kindIs "map" $items }}
          {{- $entries := dict }}
          {{- range $id, $item := $items }}
            {{- if include "base.lib.isEnabled" $item | trim }}
              {{- $entries = set $entries $id (include "base.lib.refs.entry" (dict "kind" $kind "id" $id "resource" $item "releaseName" $releaseName "releaseNamespace" $releaseNamespace "values" $values) | fromYaml) }}
            {{- end }}
          {{- end }}
          {{- if $entries }}
            {{- $kinds = set $kinds $kind $entries }}
          {{- end }}
        {{- end }}
      {{- end }}
      {{- if $kinds }}
        {{- $index = set $index $hrId $kinds }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- toYaml $index }}
{{- end }}
