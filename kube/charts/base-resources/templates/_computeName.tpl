{{- define "base-resources.computeName" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
  {{- if $resource.fullNameOverride }}
    {{- $resource.fullNameOverride }}
  {{- else }}
    {{- $resourceName := $id }}
    {{- if $resource.nameOverride }}
      {{- $resourceName = $resource.nameOverride }}
    {{- end }}
    {{- if eq $resourceName "main" }}
      {{- $rootContext.Release.Name }}
    {{- else }}
      {{- printf "%s-%s" $rootContext.Release.Name $resourceName }}
    {{- end }}
  {{- end }}
{{- end }}
