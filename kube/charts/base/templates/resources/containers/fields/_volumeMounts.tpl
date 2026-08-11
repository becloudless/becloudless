{{/*
volumeMounts used by the container.
*/}}
{{- define "base.resources.containers.fields.volumeMounts" -}}
  {{- $ctx := .ctx -}}
  {{- $rootContext := $ctx.rootContext -}}
  {{- $controllerObject := $ctx.controllerObject -}}
  {{- $containerObject := $ctx.containerObject -}}

  {{- /* Default to empty dict */ -}}
  {{- $volumesToProcess := dict -}}
  {{- $enabledVolumeMounts := list -}}

  {{- /* Collect regular volumes items */ -}}
  {{- range $identifier, $volume := $controllerObject.volumes -}}
    {{- if include "base.lib.utils.isEnabled" $volume -}}
      {{- $_ := set $volumesToProcess $identifier $volume -}}
    {{- end -}}
  {{- end -}}

  {{- range $identifier, $volumeValues := $volumesToProcess -}}
    {{- if or (empty $volumeValues.containers) (hasKey $volumeValues.containers $containerObject.identifier) -}}
      {{- $volumeMount := dict -}}
      {{- $_ := set $volumeMount "name" $identifier -}}

      {{- /* Set the default mountPath to /<name_of_the_peristence_item> */ -}}
      {{- $mountPath := (printf "/%v" $identifier) -}}
      {{- if eq "hostPath" $volumeValues.type -}}
        {{- $mountPath = $volumeValues.hostPath -}}
      {{- end -}}
      {{- if $volumeValues.path -}}
        {{- $mountPath = $volumeValues.path -}}
      {{- end -}}
      {{- $_ := set $volumeMount "mountPath" $mountPath -}}

      {{- /* Use the specified subPath if provided */ -}}
      {{- with .subPath -}}
        {{- $subPath := . -}}
        {{- $_ := set $volumeMount "subPath" $subPath -}}
      {{- end -}}

      {{- /* Use the specified readOnly setting if provided */ -}}
      {{- with .readOnly -}}
        {{- $readOnly := . -}}
        {{- $_ := set $volumeMount "readOnly" $readOnly -}}
      {{- end -}}

      {{- /* Use the specified mountPropagation setting if provided */ -}}
      {{- with .mountPropagation -}}
        {{- $mountPropagation := . -}}
        {{- $_ := set $volumeMount "mountPropagation" $mountPropagation -}}
      {{- end -}}

      {{/* override with specific container definition */}}
      {{- with dig "containers" $containerObject.identifier dict $volumeValues -}}

        {{- with .path -}}
          {{- $path := . -}}
          {{- $_ := set $volumeMount "mountPath" $path -}}
        {{- end -}}

        {{- /* Use the specified subPath if provided */ -}}
        {{- with .subPath -}}
          {{- $subPath := . -}}
          {{- $_ := set $volumeMount "subPath" $subPath -}}
        {{- end -}}

        {{- /* Use the specified readOnly setting if provided */ -}}
        {{- with .readOnly -}}
          {{- $readOnly := . -}}
          {{- $_ := set $volumeMount "readOnly" $readOnly -}}
        {{- end -}}

        {{- /* Use the specified mountPropagation setting if provided */ -}}
        {{- with .mountPropagation -}}
          {{- $mountPropagation := . -}}
          {{- $_ := set $volumeMount "mountPropagation" $mountPropagation -}}
        {{- end -}}
      {{- end -}}

      {{- $enabledVolumeMounts = append $enabledVolumeMounts $volumeMount -}}
    {{- end -}}
  {{- end -}}

  {{- with $enabledVolumeMounts -}}
    {{- . | toYaml -}}
  {{- end -}}
{{- end -}}
