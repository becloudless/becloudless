{{- /*
The script of the jobs (`files/restore.sh`) in a ConfigMap, mounted in the pods. Its name has the namespace of the app: the releases of
all the apps are installed in the same namespace. Its hash is in `restore.scriptHash`, so the name of the Job (immutable) changes with it.
*/}}
{{- define "restore-app.feature" }}
{{- $rootContext := .rootContext }}
{{- $script := $rootContext.Files.Get "files/restore.sh" }}
{{- $name := printf "restore-script-%s" (required "`restore.namespace` is required" $rootContext.Values.restore.namespace | trunc 30 | trimSuffix "-") }}
restore:
  scriptConfigMap: {{ $name | quote }}
  scriptHash: {{ $script | sha256sum | trunc 10 | quote }}
resources:
  configMaps:
    restore-script:
      fullNameOverride: {{ $name | quote }}
      data:
        restore.sh: |
{{ $script | indent 10 }}
{{- end }}
