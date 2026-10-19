{{- /*
The `flux-<name>` service account of an app is bound to cluster-admin on the namespace of the app only (RoleBinding).
An app creating cluster-scoped resources (CRDs, ClusterRoles, webhooks...) sets `apps.<name>.clusterAdmin: true`
to get cluster-admin on the whole cluster (ClusterRoleBinding) instead.

The namespace, the service account and its binding are kept (`helm.sh/resource-policy: keep`) when the app is removed from the
values. Removing an app deletes its `app-<name>` HelmRelease, whose finalizer uninstalls the release as the `flux-<name>` service
account: if the account was deleted by the same upgrade, the uninstall is skipped and the resources of the app are orphaned.
The leftovers must be deleted by hand once the release is gone.
*/}}
{{- define "app-apps.features.appsNamespaces" }}
{{- $rootContext := .rootContext }}

{{- $systemNamespaces := list "default" "kube-system" "kube-public" "kube-node-lease" }}
{{- $globalValues := include "app-apps.globalValues" (dict "rootContext" $rootContext) | fromYaml }}

{{- $namespaces := dict }}
{{- $serviceAccounts := dict }}
{{- $roleBindings := dict }}
{{- $clusterRoleBindings := dict }}
{{- $configMaps := dict }}
{{- range $name, $app := ($rootContext.Values.apps | default dict) }}
  {{- $app = $app | default dict }}
  {{- if include "base.lib.isEnabled" $app | trim }}
    {{- $namespace := $app.namespace | default $name }}
    {{- $fluxName := printf "flux-%s" $name }}

    {{- if not (has $namespace $systemNamespaces) }}
      {{- $_ := set $namespaces $namespace (dict
            "annotations" (dict "helm.sh/resource-policy" "keep")) }}
    {{- end }}

    {{- /* keep SA and bindings so flux can uninstall the release */}}
    {{- $keep := dict "helm.sh/resource-policy" "keep" }}

    {{- $_ := set $serviceAccounts $fluxName (dict
          "namespace" $namespace
          "annotations" $keep) }}

    {{- $roleRef := dict
          "apiGroup" "rbac.authorization.k8s.io"
          "kind" "ClusterRole"
          "name" "cluster-admin" }}
    {{- $subjects := dict $fluxName (dict
          "kind" "ServiceAccount"
          "name" $fluxName
          "namespace" $namespace) }}
    {{- if $app.clusterAdmin }}
      {{- $_ := set $clusterRoleBindings $fluxName (dict
            "annotations" $keep
            "roleRef" $roleRef
            "subjects" $subjects) }}
    {{- else }}
      {{- $_ := set $roleBindings $fluxName (dict
            "namespace" $namespace
            "annotations" $keep
            "roleRef" $roleRef
            "subjects" $subjects) }}
    {{- end }}

    {{- $_ := set $configMaps (printf "global-values-%s" $namespace) (dict
          "fullNameOverride" "global-values"
          "namespace" $namespace
          "data" (dict "values.yaml" $globalValues)) }}
  {{- end }}
{{- end }}

{{- dict "resources" (dict
      "namespaces" $namespaces
      "serviceAccounts" $serviceAccounts
      "roleBindings" $roleBindings
      "clusterRoleBindings" $clusterRoleBindings
      "configMaps" $configMaps) | toYaml }}
{{- end }}
