{{- /*
The values of `app.scaling` as integers. A string made of only `{{ .Values.app.scaling.<key> }}` (ex: `replicas: "{{ .Values.app.scaling.replicas }}"`)
in the resources is replaced by the value of the key, as an integer: the template engine can only give a string, which is not an integer
for the `replicas` of a Deployment (or the `replicaCount` of a public chart). It is done before the templates of the resources are
rendered, and it only applies to `.Values.app.scaling`.
*/}}
{{- define "app.loader.scalingToIntegers" }}
  {{- $scaling := ($.Values.app | default dict).scaling | default dict }}
  {{- $yaml := $.Values.resources | default dict | toYaml }}
  {{- $changed := false }}
  {{- range $marker := regexFindAll "'\\{\\{\\s*\\.Values\\.app\\.scaling\\.[A-Za-z]+\\s*\\}\\}'" $yaml -1 | uniq }}
    {{- $key := regexReplaceAll "^.*scaling\\.([A-Za-z]+).*$" $marker "${1}" }}
    {{- if not (hasKey $scaling $key) }}
      {{- fail (printf "app.scaling.%s is not a scaling value (%s)" $key (keys $scaling | sortAlpha | join ", ")) }}
    {{- end }}
    {{- $yaml = replace $marker (toString (int64 (get $scaling $key))) $yaml }}
    {{- $changed = true }}
  {{- end }}
  {{- if $changed }}
    {{- $_ := set $.Values "resources" (fromYaml $yaml) }}
  {{- end }}
{{- end }}
