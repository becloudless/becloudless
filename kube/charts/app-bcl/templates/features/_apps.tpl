{{- /*
Prepare one Flux HelmRelease per enabled app. `apps.<name>` renders `app-<name>` from `./kube/charts/app-<name>`.

An app is enabled by `apps.<name>.enabled: true` (set by the user, or by the apps-groups feature from its groups).

Any key set next to `enabled` and `groups` (ex: `values`, `interval`) is merged over the HelmRelease defaults.
*/}}
{{- define "app-bcl.features.apps" }}
{{- $rootContext := .rootContext }}

{{- $helmReleases := dict }}
{{- range $name, $app := ($rootContext.Values.apps | default dict) }}
  {{- $app = $app | default dict }}
  {{- if $app.enabled }}
    {{- $hrName := printf "app-%s" $name }}
    {{- $hr := dict
          "fullNameOverride" $hrName
          "interval" "10m"
          "timeout" "10m"
          "rollback" (dict "cleanupOnFail" true)
          "driftDetection" (dict "mode" "enabled")
          "chart" (dict "spec" (dict
            "chart" (printf "./kube/charts/%s" $hrName)
            "reconcileStrategy" "Revision"
            "sourceRef" (dict "kind" "GitRepository" "name" "bcl")))
          "valuesFrom" (dict "global" (dict "kind" "ConfigMap" "name" (printf "%s-global-values" $rootContext.Release.Name)))
    }}
    {{- $_ := set $helmReleases $name (mustMergeOverwrite $hr (omit $app "enabled" "groups")) }}
  {{- end }}
{{- end }}

{{- dict "resources" (dict "fluxHelmReleases" $helmReleases) | toYaml }}
{{- end }}
