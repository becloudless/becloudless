{{- /*
The `flux-apps` service account of the cluster-level `apps` HelmRelease, bound to cluster-admin: this release creates the
namespaces, service accounts and role bindings of every app, so it needs the permissions of the apps it installs.
Flux does not run a resource without `spec.serviceAccountName` with its own permissions, the `apps` HelmRelease of the cluster must set
`serviceAccountName: flux-apps`.
It is applied by `bcl kube bootstrap` before the HelmRelease, since the release cannot create the account it runs as, and adopted by
the release afterwards.
The account and its binding are kept (`helm.sh/resource-policy: keep`), the release must be able to run its own uninstall.
*/}}
{{- define "app-apps.features.appsServiceAccount" }}
{{- $rootContext := .rootContext }}

{{- $name := "flux-apps" }}
{{- $namespace := $rootContext.Release.Namespace }}

{{- /* keep SA and bindings so flux can uninstall the release */}}
{{- $keep := dict "helm.sh/resource-policy" "keep" }}

{{- dict "resources" (dict
      "serviceAccounts" (dict $name (dict
        "namespace" $namespace
        "annotations" $keep))
      "clusterRoleBindings" (dict $name (dict
        "annotations" $keep
        "roleRef" (dict
          "apiGroup" "rbac.authorization.k8s.io"
          "kind" "ClusterRole"
          "name" "cluster-admin")
        "subjects" (dict $name (dict
          "kind" "ServiceAccount"
          "name" $name
          "namespace" $namespace))))) | toYaml }}
{{- end }}
