{{- /*
Prepare one Flux HelmRelease `syncthing-<user>` per user of `app.lldapUsers` that is a member of the `app_syncthing` group,
installing the `syncthing` chart (one instance, see its values) with the id of the user and the `app` values (domain, name and base DN). The HelmReleases are created in
the namespace of the release and run as the same service account as the other ones of the app (`defaults.resources` of the apps chart).

The id of the user is the name of the resources, so it must be a valid DNS label (lowercase letters, digits and `-`).
The instances wait for `syncthing-pre` (values.yaml), which makes the token and the certificate of the relay they are configured from.
Set `resources.fluxHelmReleases.syncthing-<user>.values` in the cluster to configure an instance (ex: `storageSize`).
*/}}
{{- define "app-syncthing.features.instances" }}
{{- $rootContext := .rootContext }}
{{- $app := $rootContext.Values.app }}

{{- $ids := list }}
{{- range $id, $user := ($app.lldapUsers | default dict) }}
  {{- if has "app_syncthing" (($user | default dict).groups | default list) }}
    {{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $id) }}
      {{- fail (printf "the lldap user %q cannot have a Syncthing instance: its id must be a valid DNS label (lowercase letters, digits and `-`)" $id) }}
    {{- end }}
    {{- $ids = append $ids $id }}
  {{- end }}
{{- end }}

{{- if $ids }}
resources:
  fluxHelmReleases:
    {{- range $id := $ids }}
    syncthing-{{ $id }}:
      install:
        disableWait: true
      upgrade:
        disableWait: true
      dependsOn:
        - name: app-longhorn
          namespace: longhorn-system
        - name: app-cert-manager
          namespace: cert-manager
        - name: syncthing-pre
        - name: app-gateway-api
          namespace: gateway-api
      chart:
        spec:
          chart: ./kube/charts/syncthing
          reconcileStrategy: Revision
          sourceRef:
            kind: GitRepository
            name: bcl
            namespace: apps
      values:
        user: {{ $id }}
        storageClassName: longhorn-files
        app:
          domain: {{ $app.domain }}
          name: {{ $app.name }}
          lldapdn: {{ $app.lldapdn }}
    {{- end }}
{{- end }}
{{- end }}
