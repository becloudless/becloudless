{{- /*
Prepare one Flux HelmRelease per enabled app. `apps.<name>` renders `app-<name>` from `./kube/charts/app-<name>`.

An app is enabled by `apps.<name>.enabled: true` (set by the user, or by the apps-groups feature from its groups).

Any key set next to `enabled` and `groups` (ex: `values`, `interval`) is merged over the HelmRelease defaults.

`targetNamespace` makes Helm create and install the release in the namespace.
*/}}
{{- define "app-bcl.features.apps" }}
{{- $rootContext := .rootContext }}

{{- $helmReleases := dict }}
{{- range $name, $app := ($rootContext.Values.apps | default dict) }}
  {{- $app = $app | default dict }}
  {{- if $app.enabled }}
    {{- $hrName := printf "app-%s" $name }}
    {{- $hr := dict
          "interval" "10m"
          "timeout" "10m"
          "rollback" (dict "cleanupOnFail" true)
          "driftDetection" (dict "mode" "enabled")
          "chart" (dict "spec" (dict
            "chart" (printf "./kube/charts/%s" $hrName)
            "reconcileStrategy" "Revision"
            "sourceRef" (dict "kind" "GitRepository" "name" "bcl")))
          "valuesFrom" (dict "global" (dict "kind" "ConfigMap" "name" "global-values"))
    }}
    {{- /* An app owning a namespace gets it created by Helm: the namespace is not part of the release, so it survives an uninstall
           of the release. The release keeps its name and its storage in the namespace of the HelmRelease. */}}
    {{- if $app.targetNamespace }}
      {{- $_ := set $hr "releaseName" $hrName }}
      {{- $_ := set $hr "storageNamespace" $rootContext.Release.Namespace }}
      {{- $_ := set $hr "install" (dict "createNamespace" true) }}
    {{- end }}
    {{- $_ := set $helmReleases $hrName (mustMergeOverwrite $hr (omit $app "enabled" "groups")) }}
  {{- end }}
{{- end }}

{{- dict "resources" (dict "fluxHelmReleases" $helmReleases) | toYaml }}
{{- end }}
