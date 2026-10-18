{{- define "app-bcl.features.globalValues" }}
{{- $rootContext := .rootContext }}

{{- $domain := $rootContext.Values.config.domain }}
{{- if not $domain }}
    {{- fail "config.domain is required" }}
{{- end }}

{{- $name := $rootContext.Values.config.name }}
{{- if not $name }}
  {{- $name = lower (first (splitList "." $domain)) }}
{{- end }}

{{- $ldapdn := $rootContext.Values.config.ldapdn }}
{{- if not $ldapdn }}
  {{- $dcs := list }}
  {{- range splitList "." (lower $domain) }}
    {{- $dcs = append $dcs (printf "dc=%s" .) }}
  {{- end }}
  {{- $ldapdn = join "," $dcs }}
{{- end }}

resources:
  configMaps:
    global-values:
      data:
        values.yaml:
            global:
                domain: {{ $domain }}
                name: {{ $name }}
                ldapdn: {{ $ldapdn }}
{{- end }}