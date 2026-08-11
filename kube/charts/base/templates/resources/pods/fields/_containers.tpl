{{- /*
Returns the value for containers
*/ -}}
{{- define "base.resources.pods.fields.containers" -}}
  {{- $rootContext := .ctx.rootContext -}}
  {{- $controllerObject := .ctx.controllerObject -}}

  {{- /* Default to empty list */ -}}
  {{- $graph := dict -}}
  {{- $containers := list -}}

  {{- /* Fetch configured containers for this controller */ -}}
  {{- $enabledContainers := include "base.resources.controllers.enabledContainers" (dict "rootContext" $rootContext "controllerObject" $controllerObject) | fromYaml }}
  {{- $renderedContainers := dict -}}

  {{- /* TODO: Remove this logic after "order" removal in v3 */ -}}
  {{- $containersWithDependsOn := include "base.lib.getMapItemsWithKey" (dict "map" $enabledContainers "key" "dependsOn") | fromYaml | keys -}}
  {{- $useDependsOn := gt (len $containersWithDependsOn) 0 -}}

  {{- range $key, $containerValues := $enabledContainers -}}
    {{- /* Create object from the container values */ -}}
    {{- $containerObject := (include "base.resources.containers.valuesToObject" (dict "rootContext" $rootContext "id" $key "values" $containerValues)) | fromYaml -}}

    {{- /* Perform validations on the Container before rendering */ -}}
    {{- include "base.resources.containers.validate" (dict "rootContext" $ "controllerObject" $controllerObject "containerObject" $containerObject) -}}

    {{- /* Generate the Container spec */ -}}
    {{- $renderedContainer := include "base.resources.containers.class" (dict "rootContext" $rootContext "controllerObject" $controllerObject "containerObject" $containerObject) | fromYaml -}}
    {{- $_ := set $renderedContainers $key $renderedContainer -}}

    {{- /* Determine the Container order */ -}}
    {{- if $useDependsOn -}}
      {{- if empty (dig "dependsOn" nil $containerValues) -}}
        {{- $_ := set $graph $key ( list ) -}}
      {{- else if kindIs "string" $containerValues.dependsOn -}}
        {{- $_ := set $graph $key ( list $containerValues.dependsOn ) -}}
      {{- else if kindIs "slice" $containerValues.dependsOn -}}
        {{- $_ := set $graph $key $containerValues.dependsOn -}}
      {{- end -}}
    {{- else -}}
      {{- /* TODO: Remove this logic after "order" removal in v3 */ -}}
      {{- $containerOrder := (dig "order" 99 $containerValues) -}}
      {{- $_ := set $graph $key $containerOrder -}}
    {{- end -}}
  {{- end -}}

  {{- /* Process graph */ -}}
  {{- if $useDependsOn -}}
    {{- $args := dict "graph" $graph "out" list -}}
    {{- include "base.lib.kahn" $args -}}

    {{- range $name := $args.out -}}
      {{- $containerItem := get $renderedContainers $name -}}
      {{- $containers = append $containers $containerItem -}}
    {{- end -}}
  {{- else -}}
    {{- /* TODO: Remove this logic after "order" removal in v3 */ -}}
    {{- $orderedContainers := dict -}}
    {{- range $key, $order := $graph -}}
      {{- $containerItem := get $renderedContainers $key -}}
      {{- $_ := set $orderedContainers (printf "%v-%s" $order $key) $containerItem -}}
    {{- end -}}
    {{- range $key, $containerValues := $orderedContainers -}}
      {{- $containers = append $containers $containerValues -}}
    {{- end -}}
  {{- end -}}

  {{- if not (empty $containers) -}}
    {{- $containers | toYaml -}}
  {{- end -}}
{{- end -}}
