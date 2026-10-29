{{- /*
Restore the volumes of the enabled apps from the Longhorn backups, before they start (`restore` of an app).

Per app, `restore: true` opts in. The PVCs are not listed: the job finds those of the namespace in the backups.

The HelmRelease `restore-<name>`, in the namespace of the `backup-restore` app (app-backup-restore), installs the chart `restore-app`, and
`app-<name>` waits for it. The job of the chart restores the last backup of each PVC that does not exist yet, as a Longhorn volume and
a PV bound to the PVC of the app: it does nothing for an app that already has its volumes, or when there is no backup. It runs as the
`flux-backup-restore` account in the namespace of `backup-restore`, the jobs run as the account `backup-restore` of app-backup-restore, which has the rights.

It waits for Longhorn (`app-longhorn`), for `app-backup-restore` and its `backup-restore-pre` (the key of the bucket of the secrets), and for the backup
target of Garage (the HelmRelease `longhorn-backup` of app-garage) when the apps are enabled: do not set `restore` on `garage`,
`backup-restore` or `longhorn`, their volumes can not be restored before they run. Nothing is created when Longhorn or `backup-restore` is not enabled.

Only for the apps keeping all their state in their PVCs and CloudNativePG databases (both are restored, see the chart
`restore-app`), and the secrets that secret-generator generated for them: the chart saves them (hourly, in the bucket of the
backup target, under `secrets/`), and the job restores them with the volumes, before the app generates new ones that would not match the
restored data. For this, the `backup-restore` account of the jobs gets a Role in the namespace of the app: it reads, creates and
patches (the ownership of a restored secret) its secrets, and reads its `StringSecret`. The account of the app has no part in it.
*/}}
{{- define "app-apps.restore.enabled" }}
  {{- $app := get .apps .name | default dict }}
  {{- $longhorn := get .apps "longhorn" | default dict }}
  {{- $backup := get .apps "backup-restore" | default dict }}
  {{- if and (include "base.lib.isEnabled" $app | trim) $app.restore (include "base.lib.isEnabled" $longhorn | trim) (include "base.lib.isEnabled" $backup | trim) }}true{{ end }}
{{- end }}

{{- /* the namespace of the app `backup-restore` */}}
{{- define "app-apps.restore.namespace" }}
  {{- $backup := get . "backup-restore" | default dict }}
  {{- $backup.namespace | default "backup-restore" }}
{{- end }}

{{- define "app-apps.features.appsRestore" }}
{{- $rootContext := .rootContext }}

{{- $apps := $rootContext.Values.apps | default dict }}

{{- $bclRepository := (($rootContext.Values.resources | default dict).fluxGitRepositories | default dict).bcl | default dict }}
{{- $bclNamespace := $bclRepository.namespace | default $rootContext.Release.Namespace }}

{{- $longhorn := get $apps "longhorn" | default dict }}
{{- $longhornNamespace := $longhorn.namespace | default "longhorn" }}
{{- $backupNamespace := include "app-apps.restore.namespace" $apps | trim }}
{{- $garage := get $apps "garage" | default dict }}

{{- $helmReleases := dict }}
{{- $roles := dict }}
{{- $roleBindings := dict }}
{{- range $name, $app := $apps }}
  {{- $app = $app | default dict }}
  {{- if include "app-apps.restore.enabled" (dict "apps" $apps "name" $name) | trim }}
    {{- $namespace := $app.namespace | default $name }}
    {{- $dependsOn := dict
          "longhorn" (dict "name" "app-longhorn" "namespace" $longhornNamespace)
          "backup-restore" (dict "name" "app-backup-restore" "namespace" $backupNamespace)
          "backup-restore-pre" (dict "name" "backup-restore-pre" "namespace" $backupNamespace) }}
    {{- if include "base.lib.isEnabled" $garage | trim }}
      {{- $_ := set $dependsOn "backup-target" (dict "name" "longhorn-backup" "namespace" ($garage.namespace | default "garage")) }}
    {{- end }}

    {{- $_ := set $helmReleases (printf "restore-%s" $name) (dict
          "namespace" $backupNamespace
          "serviceAccountName" "flux-backup-restore"
          "interval" "1h"
          "timeout" "1h"
          "install" (dict "timeout" "1h")
          "upgrade" (dict "timeout" "1h")
          "rollback" (dict "cleanupOnFail" true)
          "dependsOn" $dependsOn
          "chart" (dict "spec" (dict
            "chart" "./kube/charts/restore-app"
            "reconcileStrategy" "Revision"
            "sourceRef" (dict "kind" "GitRepository" "name" "bcl" "namespace" $bclNamespace)))
          "values" (dict "restore" (dict "namespace" $namespace))) }}

    {{- /* the secrets of the app, for the jobs of the chart (the account is the one of app-backup-restore) */}}
    {{- $_ := set $roles (printf "backup-restore-%s" $name) (dict
          "fullNameOverride" "backup-restore"
          "namespace" $namespace
          "rules" (dict
            "secrets" (dict "apiGroups" (list "") "resources" (list "secrets") "verbs" (list "get" "list" "create" "patch"))
            "stringsecrets" (dict "apiGroups" (list "secretgenerator.mittwald.de") "resources" (list "stringsecrets") "verbs" (list "get" "list")))) }}
    {{- $_ := set $roleBindings (printf "backup-restore-%s" $name) (dict
          "fullNameOverride" "backup-restore"
          "namespace" $namespace
          "roleRef" (dict "apiGroup" "rbac.authorization.k8s.io" "kind" "Role" "name" "backup-restore")
          "subjects" (dict "backup-restore" (dict "kind" "ServiceAccount" "name" "backup-restore" "namespace" $backupNamespace))) }}
  {{- end }}
{{- end }}

resources:
  fluxHelmReleases: {{- $helmReleases | toYaml | nindent 4 }}
  roles: {{- $roles | toYaml | nindent 4 }}
  roleBindings: {{- $roleBindings | toYaml | nindent 4 }}
{{- end }}
