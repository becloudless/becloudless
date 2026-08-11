{{/* find a resource name based on the name specified, or the _resourceIdentifier, or the identifier */}}
{{- define "base.lib.resource.findResourceName" -}}
  {{- $rootContext := .rootContext -}}
  {{/* the .Values.resources.{{resourceType}}: */}}
  {{- $resourcesType := .resourcesType -}}
  {{/* the prefix to the value where we find the name or resourceIdentifier */}}
  {{- $valuePrefix := .valuePrefix -}}
  {{/* the identifier of the resource used if nothing is set explicity */}}
  {{- $identifier := .identifier -}}
  {{/* current values where to find the name or the resourceIdentifier */}}
  {{- $values := .values -}}
  {{/* fail message suffix, to give the context of the current fail */}}
  {{- $failSuffix := .failSuffix -}}
  {{/* is a resolution optional */}}
  {{- $optional := .optional -}}

  {{- $directName := index $values $valuePrefix -}}
  {{- $resourceIdentifier := index $values (printf "%s_resource" $valuePrefix) -}}

  {{/* if nothing is set, use identifier by default, if provided */}}
  {{- if and $identifier (not $directName) (not $resourceIdentifier) -}}
    {{- $resourceIdentifier = $identifier -}}
  {{- end -}}

  {{- if and $directName $resourceIdentifier -}}
    {{- fail (printf "%s and %s_resource are mutually exclusive. %s" $valuePrefix $valuePrefix $failSuffix) -}}
  {{- end -}}
  {{- if and (empty $directName) (empty $resourceIdentifier) (not $optional) -}}
    {{- fail (printf "%s or %s_resource must be set. %s" $valuePrefix $valuePrefix $failSuffix) -}}
  {{- end -}}

  {{- if $directName -}}
    {{- $directName -}}
  {{- else if $resourceIdentifier -}}
    {{- $resourceValues := dig $resourcesType $resourceIdentifier dict $rootContext.Values.resources -}}
    {{- if empty $resourceValues -}}
      {{- fail (printf "resource does not exists %s.%s" $resourcesType $resourceIdentifier) -}}
    {{- else if not (include "base.lib.utils.isEnabled" $resourceValues) -}}
      {{- fail (printf "resource is disabled %s.%s" $resourcesType $resourceIdentifier) -}}
    {{- end -}}
    {{- $object := include (printf "base.resources.%s.valuesToObject" $resourcesType) (dict "rootContext" $rootContext "id" $resourceIdentifier "values" $resourceValues) | fromYaml -}}
    {{- $object.name -}}
  {{- end -}}
{{- end -}}
