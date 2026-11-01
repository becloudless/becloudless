{{- /*
Prepare the Kyverno ClusterPolicies of the cluster, one file `files/policies/<name>.yaml` each (the content is the policy,
named after the file), as `kyvernoClusterPolicies` of the `kyverno-post` HelmRelease: they need the Kyverno CRDs, so they are
installed once kyverno is ready.

The `{{ }}` of the Kyverno variables would be rendered as templates by the chart, then by the base-loader of `kyverno-post`,
so they are escaped twice here. The escaped actions have no space, to survive the line folding of `toYaml` (a newline in
the quoted string of an action is a parse error).

Everything is returned as a default: set `resources.fluxHelmReleases.kyverno-post.values.resources.kyvernoClusterPolicies.<name>...`
to override or extend any generated field.
*/}}
{{- define "app-kyverno.policies" }}
{{- $rootContext := .rootContext }}

{{- $policies := dict }}
{{- range $file, $content := $rootContext.Files.Glob "files/policies/*.yaml" }}
  {{- $_ := set $policies (base $file | trimSuffix ".yaml") ($content | toString | fromYaml) }}
{{- end }}

{{- if $policies }}
  {{- /* the closing braces of the structure of the pretty JSON are never next to each other, only the ones of the strings are replaced */}}
  {{- $json := toPrettyJson $policies }}
  {{- range $_ := until 2 }}
    {{- $json = $json | replace "{{" "@open@" | replace "}}" "@close@" | replace "@open@" "{{\\\"{{\\\"}}" | replace "@close@" "{{\\\"}}\\\"}}" }}
  {{- end }}

resources:
  fluxHelmReleases:
    kyverno-post:
      values:
        resources:
          kyvernoClusterPolicies: {{- $json | fromJson | toYaml | nindent 12 }}
{{- end }}
{{- end }}
