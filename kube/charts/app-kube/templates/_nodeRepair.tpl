{{- /*
Prepare the ConfigMap `node-repair` of the CronJob of the same name (see values.yaml): the script is the file `files/node-repair.sh`.

Everything is returned as a default: set `resources.configMaps.node-repair...` to override or extend any generated field.
*/}}
{{- define "app-kube.nodeRepair" }}
{{- $rootContext := .rootContext }}
{{- $script := $rootContext.Files.Get "files/node-repair.sh" }}
resources:
  configMaps:
    node-repair:
      data:
        node-repair.sh: |
{{ $script | indent 10 }}
{{- end }}
