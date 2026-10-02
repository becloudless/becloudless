{{- define "base.lib.computeResourceName" }}
  {{- $rootContext := .rootContext }}
  {{- $id := .id }}
  {{- $resource := .resource | default dict }}
  {{- $name := "" }}
  {{- if $resource.fullNameOverride }}
    {{- $name = $resource.fullNameOverride }}
  {{- else }}
    {{- $resourceName := $id }}
    {{- if $resource.nameOverride }}
      {{- $resourceName = $resource.nameOverride }}
    {{- end }}
    {{- if eq $resourceName "main" }}
      {{- $name = $rootContext.Release.Name }}
    {{- else }}
      {{- $name = printf "%s-%s" $rootContext.Release.Name $resourceName }}
    {{- end }}
  {{- end }}
  {{- if gt (len $name) 63 }}
    {{- fail (printf "resource name %q (%d characters) exceeds the Kubernetes maximum of 63 characters" $name (len $name)) }}
  {{- end }}
  {{- $name }}
{{- end }}
