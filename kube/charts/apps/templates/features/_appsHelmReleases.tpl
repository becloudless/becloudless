{{- /*
Prepare one Flux HelmRelease `app-<name>` per enabled app, in the namespace of the app, installing the chart of the app as
the `flux-<name>` service account (see the namespaces feature).
The HelmReleases and Kustomizations created by the chart of the app get the same service account by default
(`defaults.resources` of its values). This is only a default: the enforcement is the `--default-service-account` flag of the flux
controllers (app-flux), which makes a resource without service account run as the unprivileged `default` one, and the
`require-flux-service-account` policy (app-kyverno).

Per app:
  - `namespace`: namespace of the app, `<name>` by default
  - `appChart`: the chart of the app. No HelmRelease is created for an app without it, only its namespace, service account and RBAC
    ex: `apps`, the service account of the HelmRelease of the cluster that installs this chart
  - `appChart.name`: chart of the app, `app-<name>` by default, from `./kube/charts/<appChart.name>`
  - `dependsOn`: `<app>: true` makes the app wait for the HelmRelease of the enabled app `<app>`; `<app>: false` removes a dependency.
    A dependency on an app that is not enabled is ignored.
  - `values`: the values of the chart of the app (`spec.values` of the HelmRelease), deep merged over the values of the chart
    ex: `apps.cilium.values.resources.fluxHelmReleases.cilium-post.values.resources.gateways.shared`

Any other key set next to these (ex: `interval`) is merged over the HelmRelease defaults.
*/}}
{{- define "app-apps.features.appsHelmReleases" }}
{{- $rootContext := .rootContext }}

{{- $apps := $rootContext.Values.apps | default dict }}

{{- /* The charts come from the `bcl` git repository of this chart, in the namespace of the release unless the cluster sets one. */}}
{{- $bclRepository := (($rootContext.Values.resources | default dict).fluxGitRepositories | default dict).bcl | default dict }}
{{- $bclNamespace := $bclRepository.namespace | default $rootContext.Release.Namespace }}

{{- $helmReleases := dict }}
{{- range $name, $app := $apps }}
  {{- $app = $app | default dict }}
  {{- if include "base.lib.isEnabled" $app | trim }}
    {{- $namespace := $app.namespace | default $name }}
    {{- $fluxName := printf "flux-%s" $name }}
    {{- $hrName := printf "app-%s" $name }}
    {{- $chartName := ($app.appChart | default dict).name | default $hrName }}
    {{- $installChart := hasKey $app "appChart" }}

    {{- if $installChart }}
    {{- $dependsOn := dict }}
    {{- range $dep, $on := ($app.dependsOn | default dict) }}
      {{- $depApp := get $apps $dep | default dict }}
      {{- if and $on (include "base.lib.isEnabled" $depApp | trim) }}
        {{- $_ := set $dependsOn $dep (dict
              "name" (printf "app-%s" $dep)
              "namespace" ($depApp.namespace | default $dep)) }}
      {{- end }}
    {{- end }}

    {{- $hr := dict
          "namespace" $namespace
          "serviceAccountName" $fluxName
          "interval" "10m"
          "timeout" "10m"
          "rollback" (dict "cleanupOnFail" true)
          "driftDetection" (dict "mode" "enabled")
          "chart" (dict "spec" (dict
            "chart" (printf "./kube/charts/%s" $chartName)
            "reconcileStrategy" "Revision"
            "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" $bclNamespace)))
          "valuesFrom" (dict "global" (dict "kind" "ConfigMap" "name" "global-values"))
          "values" (dict "defaults" (dict "resources" (dict
            "fluxHelmReleases" (dict "serviceAccountName" $fluxName)
            "fluxKustomizations" (dict "serviceAccountName" $fluxName))))
    }}
    {{- if $dependsOn }}
      {{- $_ := set $hr "dependsOn" $dependsOn }}
    {{- end }}
    {{- $_ := set $helmReleases $hrName (mustMergeOverwrite $hr (omit $app "enabled" "groups" "namespace" "appChart" "dependsOn" "clusterAdmin")) }}
    {{- end }}
  {{- end }}
{{- end }}

resources:
  fluxHelmReleases: {{- $helmReleases | toYaml | nindent 4 }}
{{- end }}
