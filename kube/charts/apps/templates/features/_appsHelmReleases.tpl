{{- define "app-apps.features.appsHelmReleases" }}
{{- $rootContext := .rootContext }}

{{- $apps := $rootContext.Values.apps | default dict }}

{{- $helmReleases := dict }}
{{- range $name, $app := $apps }}
  {{- $app = $app | default dict }}
  {{- if include "base.lib.isEnabled" $app | trim }}
    {{- $namespace := $app.namespace | default $name }}
    {{- $fluxName := printf "flux-%s" $name }}
    {{- $hrName := printf "app-%s" $name }}
    {{- $chartName := ($app.appChart | default dict).name | default $hrName }}

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
            "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" $rootContext.Release.Namespace)))
          "valuesFrom" (dict "global" (dict "kind" "ConfigMap" "name" "global-values"))
    }}
    {{- if $dependsOn }}
      {{- $_ := set $hr "dependsOn" $dependsOn }}
    {{- end }}
    {{- $_ := set $helmReleases $hrName (mustMergeOverwrite $hr (omit $app "enabled" "groups" "namespace" "appChart" "dependsOn" "clusterAdmin")) }}
  {{- end }}
{{- end }}

{{- dict "resources" (dict "fluxHelmReleases" $helmReleases) | toYaml }}
{{- end }}
