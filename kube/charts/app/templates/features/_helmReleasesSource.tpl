{{- /*
The chart of the `fluxHelmReleases` of the apps: a release that sets no `chart.spec.sourceRef` (nor a `chartRef`) is a chart of this
repository, installed from the GitRepository `bcl` of the `apps` namespace (created by the `apps` chart). Its `chart.spec` defaults to
`chart: ./kube/charts/base-loader` and `reconcileStrategy: Revision`, what it sets wins. A release with its own `sourceRef` (a
HelmRepository for example) is left as it is.
*/}}
{{- define "app.loader.helmReleasesSource" }}
  {{- $releases := ($.Values.resources | default dict).fluxHelmReleases }}
  {{- if kindIs "map" $releases }}
    {{- range $id, $release := $releases }}
      {{- if and (kindIs "map" $release) (not (hasKey $release "chartRef")) }}
        {{- $chart := $release.chart | default dict }}
        {{- $spec := $chart.spec | default dict }}
        {{- if not (hasKey $spec "sourceRef") }}
          {{- $spec = set $spec "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" "apps") }}
          {{- if not (hasKey $spec "chart") }}
            {{- $spec = set $spec "chart" "./kube/charts/base-loader" }}
          {{- end }}
          {{- if not (hasKey $spec "reconcileStrategy") }}
            {{- $spec = set $spec "reconcileStrategy" "Revision" }}
          {{- end }}
          {{- $_ := set $releases $id (set $release "chart" (set $chart "spec" $spec)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
