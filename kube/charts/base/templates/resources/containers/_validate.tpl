{{/*
Validate container values
*/}}
{{- define "base.resources.containers.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerObject := .controllerObject -}}
  {{- $containerObject := .containerObject -}}

  {{- if kindIs "slice" $containerObject.env -}}
    {{- fail (printf "Env must be a map and not a slice. (controller %s, container %s)" $controllerObject.identifier $containerObject.identifier) -}}
  {{- end -}}

  {{- if not (kindIs "map" $containerObject.image)  -}}
    {{- fail (printf "Image required to be a dictionary with repository and tag fields. (controller %s, container %s)" $controllerObject.identifier $containerObject.identifier) }}
  {{- end -}}

  {{- if empty (dig "image" "repository" nil $containerObject) -}}
    {{- fail (printf "No image repository specified for container. (controller %s, container %s)" $controllerObject.identifier $containerObject.identifier) }}
  {{- end -}}

  {{- if empty (dig "image" "tag" nil $containerObject) -}}
    {{- fail (printf "No image tag specified for container. (controller %s, container %s)" $controllerObject.identifier $containerObject.identifier) }}
  {{- end -}}
{{- end -}}
