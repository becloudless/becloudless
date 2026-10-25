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
{{- $users := keys ($auth.aclUsers | default dict) | sortAlpha }}

{{- if or $users $values.clients }}
resources:
  {{- if $users }}
  stringSecrets:
    main:
      fields:
        {{- range $user := $users }}
        {{ $user }}:
          fieldName: {{ $user }}
        {{- end }}
  {{- end }}
  {{- if $values.clients }}
  ciliumNetworkPolicies:
    main:
      {{- /* the labels of the pods of the public chart */}}
      endpointSelector:
        matchLabels:
          app.kubernetes.io/name: valkey
          app.kubernetes.io/instance: {{ $name }}
      ingress:
        clients:
          fromEndpoints: {{- $values.clients | toYaml | nindent 12 }}
          toPorts:
            valkey:
              ports:
                valkey:
                  port: "6379"
                  protocol: TCP
  {{- end }}
{{- end }}
{{- end }}
