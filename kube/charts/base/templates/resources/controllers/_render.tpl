{{/*
Renders the controller objects required by the chart.
*/}}
{{- define "base.resources.controllers.render" -}}
  {{- /* Generate named controller objects as required */ -}}
  {{- range $key, $controller := .Values.resources.controllers -}}
    {{- if include "base.lib.utils.isEnabled" $controller -}}
      {{- $controllerValues := $controller -}}

      {{- /* Create object from the raw controller values */ -}}
      {{- $controllerObject := (include "base.resources.controllers.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerValues)) | fromYaml -}}

      {{- /* Perform validations on the controller before rendering */ -}}
      {{- include "base.resources.controllers.validate" (dict "rootContext" $ "object" $controllerObject) -}}

      {{- if eq $controllerObject.type "Deployment" -}}
        {{- $deploymentObject := (include "base.resources.deployments.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerObject)) | fromYaml -}}
        {{- include "base.resources.deployments.validate" (dict "rootContext" $ "object" $deploymentObject) -}}
        {{- include "base.resources.deployments.class" (dict "rootContext" $ "object" $deploymentObject) | nindent 0 -}}
      {{- else if eq $controllerObject.type "CronJob" -}}
        {{- $cronJobObject := (include "base.resources.cronJobs.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerObject)) | fromYaml -}}
        {{- include "base.resources.cronJobs.validate" (dict "rootContext" $ "object" $cronJobObject) -}}
        {{- include "base.resources.cronJobs.class" (dict "rootContext" $ "object" $cronJobObject) | nindent 0 -}}
      {{- else if eq $controllerObject.type "DaemonSet" -}}
        {{- $daemonSetObject := (include "base.resources.daemonSets.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerObject)) | fromYaml -}}
        {{- include "base.resources.daemonSets.validate" (dict "rootContext" $ "object" $daemonSetObject) -}}
        {{- include "base.resources.daemonSets.class" (dict "rootContext" $ "object" $daemonSetObject) | nindent 0 -}}
      {{- else if eq $controllerObject.type "StatefulSet"  -}}
        {{- $statefulSetObject := (include "base.resources.statefulSets.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerObject)) | fromYaml -}}
        {{- include "base.resources.statefulSets.validate" (dict "rootContext" $ "object" $statefulSetObject) -}}
        {{- include "base.resources.statefulSets.class" (dict "rootContext" $ "object" $statefulSetObject) | nindent 0 -}}
      {{- else if eq $controllerObject.type "Job"  -}}
        {{- $jobObject := (include "base.resources.jobs.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerObject)) | fromYaml -}}
        {{- include "base.resources.jobs.validate" (dict "rootContext" $ "object" $jobObject) -}}
        {{- include "base.resources.jobs.class" (dict "rootContext" $ "object" $jobObject) | nindent 0 -}}
      {{- else if eq $controllerObject.type "InferenceService"  -}}
        {{- $inferenceServiceObject := (include "base.resources.inferenceServices.valuesToObject" (dict "rootContext" $ "id" $key "values" $controllerObject)) | fromYaml -}}
        {{- include "base.resources.inferenceServices.validate" (dict "rootContext" $ "object" $inferenceServiceObject) -}}
        {{- include "base.resources.inferenceServices.class" (dict "rootContext" $ "object" $inferenceServiceObject) | nindent 0 -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
