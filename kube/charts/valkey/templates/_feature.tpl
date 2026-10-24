{{- /*
Prepare the resources around the public valkey chart (the `valkey` subchart) of the release. These are the objects that were
duplicated in every app that has a valkey:
  - stringSecrets `main`: the generated password of each user of `valkey.auth.aclUsers`, in the secret named after the release
    (`valkey.auth.usersExistingSecret`), the key being the name of the user
  - ciliumNetworkPolicies `main`: lets the `clients` connect to valkey (none when there are no clients)

Names come from the base chart: `main` is named after the release, any other id is `<release>-<id>`.

Everything is returned as a default: set `resources.<kind>.<id>...` to override or extend any generated field.
*/}}
{{- define "valkey.feature" }}
{{- $rootContext := .rootContext }}
{{- $values := $rootContext.Values }}
{{- $name := $rootContext.Release.Name }}
{{- $auth := ($values.valkey | default dict).auth | default dict }}

{{- $fields := dict }}
{{- range $user := keys ($auth.aclUsers | default dict) | sortAlpha }}
  {{- $_ := set $fields $user (dict "fieldName" $user) }}
{{- end }}

{{- $secrets := dict }}
{{- if $fields }}
  {{- $_ := set $secrets "main" (dict "fields" $fields) }}
{{- end }}

{{- $policies := dict }}
{{- if $values.clients }}
  {{- /* the labels of the pods of the public chart */}}
  {{- $_ := set $policies "main" (dict
        "endpointSelector" (dict "matchLabels" (dict "app.kubernetes.io/name" "valkey" "app.kubernetes.io/instance" $name))
        "ingress" (dict "clients" (dict
          "fromEndpoints" $values.clients
          "toPorts" (dict "valkey" (dict "ports" (dict "valkey" (dict "port" "6379" "protocol" "TCP"))))))) }}
{{- end }}

{{- dict "resources" (dict
      "stringSecrets" $secrets
      "ciliumNetworkPolicies" $policies) | toYaml }}
{{- end }}
