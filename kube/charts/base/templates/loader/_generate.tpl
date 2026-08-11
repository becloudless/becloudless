{{/*
Secondary entrypoint and primary loader for the common chart
*/}}
{{- define "base.loader.generate" -}}

  {{- /*
    Remove all non resources values to make sure the architecture stay clean.
    At this stage in the generate, preparing kube resources MUST rely only on `resources:`
  */}}
  {{- range $key, $val := .Values }}
    {{- if and (ne $key "resources") (ne $key "global") }}
      {{ $_ := unset $.Values $key }}
    {{- end }}
  {{- end }}


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

  {{- /* TODO: improve rendering of the special cases */ -}}
  {{- include "base.resources.serviceAccounts.render" . | nindent 0 -}}
  {{- include "base.resources.controllers.render" . | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "persistentVolumeClaims") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "services") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "ingresses") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "routes") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "configMaps") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "sealedSecrets") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "secrets") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "networkPolicies") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "podDisruptionBudgets") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "horizontalPodAutoscalers") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "imageRepositories") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "imagePolicies") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "providers") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "alerts") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "sidecars") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "serviceEntries") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "virtualServices") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "destinationRules") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "authorizationPolicies") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "telemetries") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "kafkaUsers") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "envoyFilters") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "datadogMetrics") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "requestAuthentications") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "persistentVolumes") | nindent 0 -}}
  {{- include "base.lib.resource.renderResources" (dict "rootContext" $ "class" "dummies") | nindent 0 -}}
{{- end -}}
