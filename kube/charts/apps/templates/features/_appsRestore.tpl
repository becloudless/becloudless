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

Only for the apps keeping all their state in their PVCs and CloudNativePG databases (both are restored, see the chart
`longhorn-restore`), and the secrets that secret-generator generated for them: the chart saves them (hourly, in the bucket of the
backup target), and the job restores them with the volumes, before the app generates new ones that would not match the restored data.
For this, the `backup-restore` account of the jobs (see app-longhorn) gets a Role in the namespace of the app: it reads, creates and
patches (the ownership of a restored secret) its secrets, and reads its `StringSecret`. The account of the app has no part in it.
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
{{- $roles := dict }}
{{- $roleBindings := dict }}
{{- range $name, $app := $apps }}
  {{- $app = $app | default dict }}
  {{- if include "app-apps.restore.enabled" (dict "apps" $apps "name" $name) | trim }}
    {{- $namespace := $app.namespace | default $name }}
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
          "values" (dict "restore" (dict "namespace" $namespace))) }}

    {{- /* the secrets of the app, for the jobs of the chart (the account is the one of app-longhorn) */}}
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
          "subjects" (dict "backup-restore" (dict "kind" "ServiceAccount" "name" "backup-restore" "namespace" $longhornNamespace))) }}
  {{- end }}
{{- end }}

resources:
  fluxHelmReleases: {{- $helmReleases | toYaml | nindent 4 }}
  roles: {{- $roles | toYaml | nindent 4 }}
  roleBindings: {{- $roleBindings | toYaml | nindent 4 }}
{{- end }}
