{{/*
Validate CronJob values
*/}}
{{- define "base.resources.cronJobs.validate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $cronJobValues := .object -}}

  {{- if not $cronJobValues.cronJob.schedule -}}
    {{- fail (printf "cronJob.schedule is mandatory for CronJob controller type. (controller: %s)" $cronJobValues.identifier) }}
  {{- end -}}
  {{- if and (ne $cronJobValues.pod.restartPolicy "Never") (ne $cronJobValues.pod.restartPolicy "OnFailure") -}}
    {{- fail (printf "Not a valid restartPolicy type for CronJob. (controller: %s, restartPolicy: %s)" $cronJobValues.identifier $cronJobValues.pod.restartPolicy) }}
  {{- end -}}
{{- end -}}
