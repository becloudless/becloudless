{{/* Apply root features */}}
{{- define "base.features" -}}

  {{/*
    Save values set directly on the resources, before rendering any feature, to re-apply them along the road.
    We are doing that to allow features to do mergeOverwrite and so being able to run them mutiple times.
    So downstream charts can run base features mutiple times, before downstream features to read result AND render values for base features.
    */}}
  {{- if not (hasKey . "finalResourceOverrideValues") }}
    {{- $resources := deepCopy .Values.resources }}
    {{- $_ := set . "finalResourceOverrideValues" $resources }}
  {{- end }}

  {{- include "base.features.environment" (dict "rootContext" $) -}}
  {{- include "base.features.mainWorkload" $ -}}
  {{- include "base.features.workloads" (dict "rootContext" $) -}}

  {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj"  (include "base.features.istio" $ | fromYaml)) -}}

  {{/* resources default should be applied at the end to let other features enable some resources if needed */}}
  {{- include "base.features.chartDefaultsResources" $ -}}

  {{/* re-apply values set directly on resources since they win over any feature */}}
  {{- $_ := mergeOverwrite .Values.resources .finalResourceOverrideValues }}

  {{/* debug should be done last so the configmap contains all generated values */}}
  {{- $_ := mergeOverwrite .Values (include "base.features.debug" (dict "rootContext" $ "chartName" "base") | fromYaml) -}}
{{- end -}}
