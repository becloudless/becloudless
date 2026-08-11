{{/* render all resources for a class kind */}}
{{- define "base.lib.resource.renderResources" -}}
  {{- $rootContext := .rootContext -}}
  {{- $class := .class -}}

  {{- range $key, $resourceValues := (dig $class dict $rootContext.Values.resources) }}
    {{- if include "base.lib.utils.isEnabled" $resourceValues -}}

      {{- /* Create object from the raw values */ -}}
      {{- $object := (include (printf "base.resources.%s.valuesToObject" $class) (dict "rootContext" $rootContext "id" $key "values" $resourceValues)) | fromYaml -}}

      {{- /* Perform validations on the object before rendering */ -}}
      {{- include (printf "base.resources.%s.validate" $class) (dict "rootContext" $rootContext "object" $object) -}}

      {{/* Include the resource class */}}
      {{- include (printf "base.resources.%s.class" $class) (dict "rootContext" $rootContext "object" $object) | nindent 0 -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
