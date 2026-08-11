{{- /*
Returns the value for volumes
*/ -}}
{{- define "base.resources.pods.fields.volumes" -}}
  {{- $rootContext := .ctx.rootContext -}}
  {{- $controllerObject := .ctx.controllerObject -}}

  {{- /* Default to empty list */ -}}
  {{- $volumesToProcess := dict -}}
  {{- $volumes := list -}}

  {{- /* Loop over volumes values */ -}}
  {{- range $identifier, $volume := $controllerObject.volumes -}}
    {{- if include "base.lib.utils.isEnabled" $volume -}}
      {{- if empty $volume.type  -}}
        {{- fail (printf "volume type is mandatory. (controller: %s, volume: %s)" $controllerObject.identifier $identifier) -}}
      {{- end -}}

      {{- $hasglobalMounts := not (empty $volume.globalMounts) -}}
      {{- $globalMounts := dig "globalMounts" list $volume -}}

      {{- $hasAdvancedMounts := not (empty $volume.advancedMounts) -}}
      {{- $advancedMounts := dig "advancedMounts" $controllerObject.identifier list $volume -}}

      {{ if or
        ($hasglobalMounts)
        (and ($hasAdvancedMounts) (not (empty $advancedMounts)))
        (and (not $hasglobalMounts) (not $hasAdvancedMounts))
      -}}
        {{- $_ := set $volumesToProcess $identifier $volume -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- /* Loop over volume items */ -}}
  {{- range $identifier, $volumeValues := $volumesToProcess -}}
    {{- $volume := dict "name" $identifier -}}

    {{- /* PVC volume type */ -}}
    {{- if eq $volumeValues.type "persistentVolumeClaim" -}}
      {{- $name := include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "persistentVolumeClaims" "identifier" $identifier "valuePrefix" "name" "values" $volumeValues "failSuffix" (printf "controller: %s (volume: %s)" $controllerObject.identifier $identifier)) -}}
      {{- $_ := set $volume "persistentVolumeClaim" (dict "claimName" $name) -}}
    
    {{- /* volumeClaim volume type: we don't want the volume, only the volumeMount is needed */ -}}
    {{- else if eq $volumeValues.type "volumeClaim" -}}
      {{- continue -}}
    
    {{- /* configMap volume type */ -}}
    {{- else if eq $volumeValues.type "configMap" -}}
      {{- $name := include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "configMaps" "identifier" $identifier "valuePrefix" "name" "values" $volumeValues "failSuffix" (printf "controller: %s (volume: %s)" $controllerObject.identifier $identifier)) -}}
      {{- $_ := set $volume "configMap" dict -}}
      {{- $_ := set $volume.configMap "name" $name -}}
      {{- with $volumeValues.defaultMode -}}
        {{- $_ := set $volume.configMap "defaultMode" . -}}
      {{- end -}}
      {{- with $volumeValues.items -}}
        {{- $_ := set $volume.configMap "items" . -}}
      {{- end -}}

    {{- /* Secret volume type */ -}}
    {{- else if eq $volumeValues.type "secret" -}}
      {{- $name := include "base.lib.resource.findResourceName" (dict "rootContext" $rootContext "resourcesType" "sealedSecrets" "identifier" $identifier "valuePrefix" "name" "values" $volumeValues "failSuffix" (printf "controller: %s (volume: %s)" $controllerObject.identifier $identifier)) -}}
      {{- $_ := set $volume "secret" dict -}}
      {{- $_ := set $volume.secret "secretName" $name -}}
      {{- with $volumeValues.defaultMode -}}
        {{- $_ := set $volume.secret "defaultMode" . -}}
      {{- end -}}
      {{- with $volumeValues.items -}}
        {{- $_ := set $volume.secret "items" . -}}
      {{- end -}}

    {{- /* emptyDir volume type */ -}}
    {{- else if eq $volumeValues.type "emptyDir" -}}
      {{- $_ := set $volume "emptyDir" dict -}}
      {{- with $volumeValues.medium -}}
        {{- $_ := set $volume.emptyDir "medium" . -}}
      {{- end -}}
      {{- with $volumeValues.sizeLimit -}}
        {{- $_ := set $volume.emptyDir "sizeLimit" . -}}
      {{- end -}}

    {{- /* hostPath volume type */ -}}
    {{- else if eq $volumeValues.type "hostPath" -}}
      {{- $_ := set $volume "hostPath" dict -}}
      {{- $_ := set $volume.hostPath "path" (required "hostPath not set" $volumeValues.hostPath) -}}
      {{- with $volumeValues.hostPathType }}
        {{- $_ := set $volume.hostPath "type" . -}}
      {{- end -}}

    {{- /* nfs volume type */ -}}
    {{- else if eq $volumeValues.type "nfs" -}}
      {{- $_ := set $volume "nfs" dict -}}
      {{- $_ := set $volume.nfs "server" (required "server not set" $volumeValues.server) -}}
      {{- $_ := set $volume.nfs "path" (required "nfsPath not set" $volumeValues.nfsPath) -}}

    {{- /* DownwardAPI volume type */ -}}
    {{- else if eq $volumeValues.type "downwardAPI" -}}
      {{- $items := list }}
      {{- range $path, $fieldPath := (required "fieldRefPaths not set" $volumeValues.fieldRefPaths) -}}
        {{- $item := dict "path" $path "fieldRef" (dict "fieldPath" $fieldPath) -}}
        {{- $items = append $items $item -}}
      {{- end -}}
      {{- $_ := set $volume "downwardAPI" (dict "items" $items) -}}

    {{- /* custom volume type */ -}}
    {{- else if eq $volumeValues.type "custom" -}}
      {{- $volume = (tpl ($volumeValues.volumeSpec | toYaml) $rootContext) | fromYaml -}}
      {{- $_ := set $volume "name" $identifier -}}

    {{- /* Fail otherwise */ -}}
    {{- else -}}
      {{- fail (printf "Not a valid volume type. (controller: %s, volume: %s)" $controllerObject.identifier $identifier) -}}
    {{- end -}}

    {{/* check that specific container override point to an existing container */}}
    {{- range $index, $_ := $volumeValues.containers -}}
      {{- if and (not (hasKey $controllerObject.containers $index)) (not (hasKey (dig "initContainers" dict $controllerObject) $index)) -}}
        {{- fail (printf "volume specific container configuration point to a non existing container. (controller: %s, volume: %s, container: %s)" $controllerObject.identifier $identifier $index) -}}
      {{- end -}}
    {{- end -}}

    {{- $volumes = append $volumes $volume -}}
  {{- end -}}

  {{- if not (empty $volumes) -}}
    {{- $volumes | toYaml -}}
  {{- end -}}
{{- end -}}
