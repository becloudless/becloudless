{{- define "base.features.chartDefaultsResources" -}}
   {{- range $controllerId, $controller := .Values.resources.controllers -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controller)))) }}

    {{- if and (eq $controller.type "InferenceService") (get $.Values.chartDefaults.resources.controllers "inferenceService") -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controllers.inferenceService)))) }}
    {{- end -}}
    {{- if and (eq $controller.type "CronJob") (get $.Values.chartDefaults.resources.controllers "cronJob") -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controllers.cronJob)))) }}
    {{- end -}}
    {{- if and (eq $controller.type "Job") (get $.Values.chartDefaults.resources.controllers "job") -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controllers.job)))) }}
    {{- end -}}
    {{- if and (eq $controller.type "DaemonSet") (get $.Values.chartDefaults.resources.controllers "daemonSet") -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controllers.daemonSet)))) }}
    {{- end -}}
    {{- if and (eq $controller.type "StatefulSet") (get $.Values.chartDefaults.resources.controllers "statefulSet") -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controllers.statefulSet)))) }}
    {{- end -}}
    {{- if and (eq $controller.type "Deployment") (get $.Values.chartDefaults.resources.controllers "deployment") -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId $.Values.chartDefaults.resources.controllers.deployment)))) }}
    {{- end -}}


    {{- range $containerId, $container := $controller.containers -}}
      {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "controllers" (dict $controllerId (dict "containers" (dict $containerId $.Values.chartDefaults.resources.container)))))) }}
    {{- end -}}
  {{- end -}}

  {{- range $identifier, $pdb := .Values.resources.podDisruptionBudgets -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "podDisruptionBudgets" (dict $identifier $.Values.chartDefaults.resources.podDisruptionBudget)))) }}
  {{- end -}}

  {{- range $identifier, $hpa := .Values.resources.horizontalPodAutoscalers -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "horizontalPodAutoscalers" (dict $identifier $.Values.chartDefaults.resources.horizontalPodAutoscaler)))) }}
  {{- end -}}

  {{- range $identifier, $service := .Values.resources.services -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "services" (dict $identifier $.Values.chartDefaults.resources.service)))) }}
  {{- end -}}

  {{- range $identifier, $imagePolicy := .Values.resources.imagePolicies -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "imagePolicies" (dict $identifier $.Values.chartDefaults.resources.imagePolicy)))) }}
  {{- end -}}

  {{- range $identifier, $imageRepository := .Values.resources.imageRepositories -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "imageRepositories" (dict $identifier $.Values.chartDefaults.resources.imageRepository)))) }}
  {{- end -}}

  {{- range $identifier, $networkPolicy := .Values.resources.networkPolicies -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "networkPolicies" (dict $identifier $.Values.chartDefaults.resources.networkPolicy)))) }}
  {{- end -}}

  {{- range $identifier, $persistentVolumeClaim := .Values.resources.persistentVolumeClaims -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "persistentVolumeClaims" (dict $identifier $.Values.chartDefaults.resources.persistentVolumeClaim)))) }}
  {{- end -}}

  {{- range $identifier, $persistentVolume := .Values.resources.persistentVolumes -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "persistentVolumes" (dict $identifier $.Values.chartDefaults.resources.persistentVolume)))) }}
  {{- end -}}

  {{- range $identifier, $sidecar := .Values.resources.sidecars -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "sidecars" (dict $identifier $.Values.chartDefaults.resources.sidecar)))) }}
  {{- end -}}

  {{- range $identifier, $virtualService := .Values.resources.virtualServices -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "virtualServices" (dict $identifier $.Values.chartDefaults.resources.virtualService)))) }}
  {{- end -}}

  {{- range $identifier, $destinationRule := .Values.resources.destinationRules -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "destinationRules" (dict $identifier $.Values.chartDefaults.resources.destinationRule)))) }}
  {{- end -}}

  {{- range $identifier, $serviceEntry := .Values.resources.serviceEntries -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "serviceEntries" (dict $identifier $.Values.chartDefaults.resources.serviceEntry)))) }}
  {{- end -}}

  {{- range $identifier, $telemetry := .Values.resources.telemetries -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "telemetries" (dict $identifier $.Values.chartDefaults.resources.telemetry)))) }}
  {{- end -}}

  {{- range $identifier, $authorizationPolicy := .Values.resources.authorizationPolicies -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "authorizationPolicies" (dict $identifier $.Values.chartDefaults.resources.authorizationPolicy)))) }}
  {{- end -}}

  {{- range $identifier, $gateway := .Values.resources.gateways -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "gateways" (dict $identifier $.Values.chartDefaults.resources.gateway)))) }}
  {{- end -}}

  {{- range $identifier, $envoyFilter := .Values.resources.envoyFilters -}}
    {{- include "base.lib.utils.mergeInValuesNonOverwrite" (dict "rootContext" $ "obj" (dict "resources" (dict "envoyFilters" (dict $identifier $.Values.chartDefaults.resources.envoyFilter)))) }}
  {{- end -}}

{{- end -}}
