{{/*
Name used by the container.
*/}}
{{- define "base.resources.containers.fields.name" -}}
  {{- $ctx := .ctx -}}
  {{- $rootContext := $ctx.rootContext -}}
  {{- $containerObject := $ctx.containerObject -}}

  {{- /* Default to container identifier */ -}}
  {{- $name := $containerObject.identifier -}}

  {{- /* See if an override is desired */ -}}
  {{- if hasKey $containerObject "nameOverride" -}}
    {{- $option := get $containerObject "nameOverride" -}}
    {{- if not (empty $option) -}}
      {{- $name = $option -}}
    {{- end -}}
  {{- end -}}

  {{- /* Parse any templates */ -}}
  {{- $name = tpl $name $rootContext -}}

  {{- $name | toYaml -}}
{{- end -}}
