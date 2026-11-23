{{- /*
Prepare the ConfigMap `volume-repair` of the CronJob of the same name (see values.yaml): the script is the file `files/volume-repair.sh`.

Everything is returned as a default: set `resources.configMaps.volume-repair...` to override or extend any generated field.
*/}}
{{- define "app-cnpg.volumeRepair" }}
{{- $rootContext := .rootContext }}
{{- $script := $rootContext.Files.Get "files/volume-repair.sh" }}
resources:
  configMaps:
    volume-repair:
      data:
        volume-repair.sh: |
{{ $script | indent 10 }}
{{- end }}
