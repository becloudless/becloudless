{{- define "base.features.environment" -}}
  {{- $rootContext := .rootContext -}}

  {{- if $rootContext.Values.kubeClusterName -}}
    {{- $VALID_CLUSTER_NAMES := (list "staging-1" "tools-1" "preprod-1" "prod-1" "prod-pmp-1" "yc-staging-1" "yc-prod-1") -}}

    {{- (include "base.lib.utils.failOnInvalidEnum" (dict "enumName" "kubeClusterName"
                                                          "dict" $rootContext.Values
                                                          "validValues" $VALID_CLUSTER_NAMES
                                                          "failIfEmpty" true)) -}}

    {{- $_ := set $rootContext "environment" (regexReplaceAll "^(yc-)?([^-]*)(-pmp)?-\\d" $rootContext.Values.kubeClusterName "${2}") -}}
  {{- end -}}
{{- end -}}
