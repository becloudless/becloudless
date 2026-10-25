{{- /*
Restore the volumes of the enabled apps from the Longhorn backups, before they start (`restore` of an app).

Per app, `restore: true` opts in. The PVCs are not listed: the job finds those of the namespace in the backups.

The HelmRelease `restore-<name>`, in the namespace of Longhorn, installs the chart `longhorn-restore`, and `app-<name>` waits
for it. The job of the chart restores the last backup of each PVC that does not exist yet, as a Longhorn volume and a PV bound to
the PVC of the app: it does nothing for an app that already has its volumes, or when there is no backup. It runs as the `flux-longhorn`
account in `longhorn-system`, the Role of its own account is in app-longhorn.

It waits for Longhorn (`app-longhorn`) and for the backup target of Garage (the HelmRelease `longhorn-backup` of app-garage) when the
apps are enabled: do not set `restore` on `garage` or `longhorn`, their volumes can not be restored before they run.
Nothing is created when Longhorn is not enabled.

Only the volumes holding all the state of an app are to be restored: the files of an app whose database is a CloudNativePG cluster
would not match the new empty database.
*/}}
{{- define "app-apps.restore.enabled" }}
  {{- $app := get .apps .name | default dict }}
  {{- $longhorn := get .apps "longhorn" | default dict }}
  {{- if and (include "base.lib.isEnabled" $app | trim) $app.restore (include "base.lib.isEnabled" $longhorn | trim) }}true{{ end }}
{{- end }}

{{- define "app-apps.features.appsRestore" }}
{{- $rootContext := .rootContext }}

{{- $apps := $rootContext.Values.apps | default dict }}

{{- $bclRepository := (($rootContext.Values.resources | default dict).fluxGitRepositories | default dict).bcl | default dict }}
{{- $bclNamespace := $bclRepository.namespace | default $rootContext.Release.Namespace }}

{{- $longhorn := get $apps "longhorn" | default dict }}
{{- $longhornNamespace := $longhorn.namespace | default "longhorn" }}
{{- $garage := get $apps "garage" | default dict }}

{{- $helmReleases := dict }}
{{- range $name, $app := $apps }}
  {{- $app = $app | default dict }}
  {{- if include "app-apps.restore.enabled" (dict "apps" $apps "name" $name) | trim }}
    {{- $dependsOn := dict "longhorn" (dict "name" "app-longhorn" "namespace" $longhornNamespace) }}
    {{- if include "base.lib.isEnabled" $garage | trim }}
      {{- $_ := set $dependsOn "backup-target" (dict "name" "longhorn-backup" "namespace" ($garage.namespace | default "garage")) }}
    {{- end }}

    {{- $_ := set $helmReleases (printf "restore-%s" $name) (dict
          "namespace" $longhornNamespace
          "serviceAccountName" "flux-longhorn"
          "interval" "1h"
          "timeout" "1h"
          "install" (dict "timeout" "1h")
          "upgrade" (dict "timeout" "1h")
          "rollback" (dict "cleanupOnFail" true)
          "dependsOn" $dependsOn
          "chart" (dict "spec" (dict
            "chart" "./kube/charts/longhorn-restore"
            "reconcileStrategy" "Revision"
            "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" $bclNamespace)))
          "values" (dict "restore" (dict "namespace" ($app.namespace | default $name)))) }}
  {{- end }}
{{- end }}

resources:
  fluxHelmReleases: {{- $helmReleases | toYaml | nindent 4 }}
{{- end }}
