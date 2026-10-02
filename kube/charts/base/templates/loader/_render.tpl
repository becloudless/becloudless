{{- define "base.loader.render" }}

  {{- with .Values.resources -}}
    {{- range $kind, $content := . -}}
        {{- if not (or (kindIs "map" $content) (kindIs "invalid" $content)) -}}
          {{- fail (printf "resources.%s must be a list of resources indexed by an identifier" $kind) -}}
        {{- end -}}
      {{- range $id, $resource := $content -}}
        {{- if not (kindIs "map" $resource) -}}
          {{- fail (printf "resources.%s.%s must be a resource indexed by an identifier" $kind $id) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

{{- end -}}
