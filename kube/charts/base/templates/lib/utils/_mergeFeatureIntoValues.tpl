{{/*
Function that merges .obj into Values and re-applies resource override on top
*/}}
{{- define "base.lib.utils.mergeOverwriteValues" -}}
  {{- $rootContext := .rootContext -}}
  {{- $obj := .obj -}}

  {{- $_ := mergeOverwrite $rootContext.Values .obj -}}
  {{/* re-apply override of resources values on top of obj */}}
  {{- $_ := mergeOverwrite $rootContext.Values.resources $rootContext.finalResourceOverrideValues }}
{{- end -}}
