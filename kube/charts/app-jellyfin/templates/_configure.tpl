{{- /*
Prepare the ConfigMap `jellyfin-scripts` of the HelmRelease `jellyfin`, mounted in the `configure` container (see values.yaml): the script is the file `files/configure.js`.

Everything is returned as a default: set `resources.fluxHelmReleases.jellyfin.values.resources.configMaps.jellyfin-scripts...` to override or extend any generated field.
*/}}
{{- define "app-jellyfin.configure" }}
{{- $rootContext := .rootContext }}
{{- $script := $rootContext.Files.Get "files/configure.js" }}
resources:
  fluxHelmReleases:
    jellyfin:
      values:
        resources:
          configMaps:
            jellyfin-scripts:
              data:
                configure.js: |
{{ $script | indent 18 }}
{{- end }}
