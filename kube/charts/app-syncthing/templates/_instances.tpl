{{- /*
Prepare one Flux HelmRelease `syncthing-<user>` per user of `global.lldapUsers` that is a member of the `app_syncthing` group,
installing the `syncthing` chart (one instance, see its values) with the id of the user and the domain. The HelmReleases are created in
the namespace of the release and run as the same service account as the other ones of the app (`defaults.resources` of the apps chart).

The id of the user is the name of the resources, so it must be a valid DNS label (lowercase letters, digits and `-`).
The instances wait for `syncthing-pre` (values.yaml), which makes the token and the certificate of the relay they are configured from.
Set `resources.fluxHelmReleases.syncthing-<user>.values` in the cluster to configure an instance (ex: `storageSize`).
*/}}
{{- define "app-syncthing.features.instances" }}
{{- $rootContext := .rootContext }}
{{- $global := $rootContext.Values.global | default dict }}
{{- $domain := required "`global.domain` is required" $global.domain }}

{{- $helmReleases := dict }}
{{- range $id, $user := ($global.lldapUsers | default dict) }}
  {{- if has "app_syncthing" (($user | default dict).groups | default list) }}
  {{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $id) }}
    {{- fail (printf "the lldap user %q cannot have a Syncthing instance: its id must be a valid DNS label (lowercase letters, digits and `-`)" $id) }}
  {{- end }}
  {{- $_ := set $helmReleases (printf "syncthing-%s" $id) (dict
        "install" (dict "disableWait" true)
        "upgrade" (dict "disableWait" true)
        "dependsOn" (dict
          "longhorn" (dict "name" "app-longhorn" "namespace" "longhorn-system")
          "cert-manager" (dict "name" "app-cert-manager" "namespace" "cert-manager")
          "syncthing-pre" (dict "name" "syncthing-pre")
          "gateway-api" (dict "name" "app-gateway-api" "namespace" "gateway-api"))
        "chart" (dict "spec" (dict
          "chart" "./kube/charts/syncthing"
          "reconcileStrategy" "Revision"
          "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" "apps")))
        "values" (dict "user" $id "global" (dict "domain" $domain))) }}
  {{- end }}
{{- end }}

{{- dict "resources" (dict "fluxHelmReleases" $helmReleases) | toYaml }}
{{- end }}
