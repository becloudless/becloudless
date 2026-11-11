{{- /*
Prepare the ConfigMap `replica-repair` of the CronJob of the same name (see values.yaml): the script is the file `files/replica-repair.sh`.

Everything is returned as a default: set `resources.configMaps.replica-repair...` to override or extend any generated field.
*/}}
{{- define "app-cnpg.replicaRepair" }}
{{- $rootContext := .rootContext }}
{{- $script := $rootContext.Files.Get "files/replica-repair.sh" }}
resources:
  configMaps:
    replica-repair:
      data:
        replica-repair.sh: |
{{ $script | indent 10 }}
{{- end }}
