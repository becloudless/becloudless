{{- /*
The OIDC clients of authelia (`oidcClients` of the values): the key is the id of the client. The apps copy the secret of their client with
`oidc` (see `app.loader.oidc` in the app library). It generates, in the releases `authelia-pre` and `authelia`:
  - the secrets `authelia-oidc-<id>` (keys `client-id` and `secret`), the Role `<id>-secrets-reader` that allows to read only this one,
    and its RoleBinding for the ServiceAccount `authelia-reader` of the namespace `namespace` (the id by default);
  - the secret `additionalSecrets` of the chart (mounted in `/secrets/authelia-oidc-<id>`) and its mount in the init container
    `oidc-hashes`, which has to be set in `pod.initContainers` of the release (it makes the hashes of the secrets, in
    `/config/oidc-<id>.hash`);
  - the authorization policy `<id>_authz` (`default_policy: deny`) and the client.
The releases of the chart are merged with the generated ones, the chart wins; the clients of the chart are kept, the generated ones are
added after them.
Options of a client:
  - `redirectUris` (required): the redirect URIs. `{clientId}` is replaced by the client id.
  - `name`: the display name (the id with a capital by default); `scopes` (`openid profile email`).
  - `groups`: the groups that pass with the second factor (`role_admin` and `app_<id>`), `oneFactorGroups`: the groups that pass with the
    first factor only (none). `policy`: the name of a policy of authelia (`two_factor`...) used instead of the generated `<id>_authz`.
  - `pkce`: requires PKCE (S256), `false` by default.
  - `claimsPolicy`: the name of a claims policy of the configuration of authelia.
  - `tokenEndpointAuthMethod` (`client_secret_basic`), `signingAlgorithm` of the access token and of the userinfo (`none`), `grantTypes`
    (`authorization_code`), `responseModes` (not set).
The client ids are generated, authelia reads them from the files of the secrets with its template filter (`X_AUTHELIA_CONFIG_FILTERS`).
*/}}
{{- define "app-authelia.features.oidcClients" }}
  {{- $clients := $.Values.oidcClients }}
  {{- if $clients }}
    {{- if not (kindIs "map" $clients) }}
      {{- fail "oidcClients must be a map, keyed by the id of the OIDC client" }}
    {{- end }}
    {{- $allowed := list "namespace" "name" "redirectUris" "scopes" "groups" "oneFactorGroups" "policy" "pkce" "claimsPolicy" "tokenEndpointAuthMethod" "signingAlgorithm" "grantTypes" "responseModes" }}
    {{- $resources := $.Values.resources | default dict }}
    {{- $releases := $resources.fluxHelmReleases | default dict }}
    {{- $backtick := "`" }}

    {{- $stringSecrets := dict }}
    {{- $roles := dict }}
    {{- $roleBindings := dict }}
    {{- $additionalSecrets := dict }}
    {{- $mounts := list }}
    {{- $policies := dict }}
    {{- $list := list }}
    {{- range $id := keys $clients | sortAlpha }}
      {{- $entry := get $clients $id | default dict }}
      {{- range $key := keys $entry }}
        {{- if not (has $key $allowed) }}
          {{- fail (printf "oidcClients.%s.%s is not an option (%s)" $id $key (join ", " $allowed)) }}
        {{- end }}
      {{- end }}
      {{- if not $entry.redirectUris }}
        {{- fail (printf "oidcClients.%s.redirectUris is required" $id) }}
      {{- end }}

      {{- $secretName := printf "authelia-oidc-%s" $id }}
      {{- $reader := printf "%s-secrets-reader" $id }}
      {{- $_ := set $stringSecrets $secretName (dict "fields" (dict "client-id" (dict) "secret" (dict))) }}
      {{- $_ := set $roles $reader (dict "rules" (dict "secrets" (dict
            "apiGroups" (list "")
            "resources" (list "secrets")
            "resourceNames" (list $secretName)
            "verbs" (list "get")))) }}
      {{- $_ := set $roleBindings $reader (dict
            "roleRef" (printf "ref:%s" $reader)
            "subjects" (dict "authelia-reader" (dict "kind" "ServiceAccount" "name" "authelia-reader" "namespace" ($entry.namespace | default $id)))) }}
      {{- $_ := set $additionalSecrets $secretName (dict) }}
      {{- $mounts = append $mounts (dict "name" (printf "secret-%s" $secretName) "mountPath" (printf "/secrets/%s" $secretName) "readOnly" true) }}

      {{- $policy := $entry.policy }}
      {{- if not $policy }}
        {{- $policy = printf "%s_authz" $id }}
        {{- $twoFactor := list }}
        {{- range $group := ($entry.groups | default (list "role_admin" (printf "app_%s" $id))) }}
          {{- $twoFactor = append $twoFactor (printf "group:%s" $group) }}
        {{- end }}
        {{- $rules := list (dict "policy" "two_factor" "subject" $twoFactor) }}
        {{- if $entry.oneFactorGroups }}
          {{- $oneFactor := list }}
          {{- range $group := $entry.oneFactorGroups }}
            {{- $oneFactor = append $oneFactor (printf "group:%s" $group) }}
          {{- end }}
          {{- $rules = append $rules (dict "policy" "one_factor" "subject" $oneFactor) }}
        {{- end }}
        {{- $_ := set $policies $policy (dict "default_policy" "deny" "rules" $rules) }}
      {{- end }}

      {{- /* the template filter of authelia (secret of the file of the client id), escaped for the rendering of the values */}}
      {{- $clientId := printf "{{ %s{{ secret %q }}%s }}" $backtick (printf "/secrets/%s/client-id" $secretName) $backtick }}
      {{- $redirectUris := list }}
      {{- range $uri := $entry.redirectUris }}
        {{- $redirectUris = append $redirectUris (replace "{clientId}" $clientId $uri) }}
      {{- end }}
      {{- $pkce := eq (toString $entry.pkce) "true" }}
      {{- $algorithm := $entry.signingAlgorithm | default "none" }}
      {{- $client := dict
            "client_id" $clientId
            "client_name" ($entry.name | default (title $id))
            "client_secret" (dict "path" (printf "/config/oidc-%s.hash" $id))
            "public" false
            "authorization_policy" $policy
            "require_pkce" $pkce
            "pkce_challenge_method" (ternary "S256" "" $pkce)
            "pre_configured_consent_duration" "1 year"
            "redirect_uris" $redirectUris
            "scopes" ($entry.scopes | default (list "openid" "profile" "email"))
            "response_types" (list "code")
            "grant_types" ($entry.grantTypes | default (list "authorization_code"))
            "access_token_signed_response_alg" $algorithm
            "userinfo_signed_response_alg" $algorithm
            "token_endpoint_auth_method" ($entry.tokenEndpointAuthMethod | default "client_secret_basic") }}
      {{- if $entry.claimsPolicy }}
        {{- $_ := set $client "claims_policy" $entry.claimsPolicy }}
      {{- end }}
      {{- if $entry.responseModes }}
        {{- $_ := set $client "response_modes" $entry.responseModes }}
      {{- end }}
      {{- $list = append $list $client }}
    {{- end }}

    {{- include "app.lib.mergeRelease" (dict "releases" $releases "name" "authelia-pre" "generated" (dict "values" (dict "resources" (dict
          "stringSecrets" $stringSecrets
          "roles" $roles
          "roleBindings" $roleBindings)))) }}

    {{- /* the lists of the values of the chart are not merged: the clients of the chart are completed, and the init container gets the mounts */}}
    {{- $authelia := get $releases "authelia" | default dict }}
    {{- $givenClients := dig "values" "configMap" "identity_providers" "oidc" "clients" list $authelia }}
    {{- include "app.lib.mergeRelease" (dict "releases" $releases "name" "authelia" "generated" (dict "values" (dict
          "secret" (dict "additionalSecrets" $additionalSecrets)
          "configMap" (dict "identity_providers" (dict "oidc" (dict
            "authorization_policies" $policies
            "clients" $list)))))) }}
    {{- $merged := get $releases "authelia" }}
    {{- $oidcValues := dig "values" "configMap" "identity_providers" "oidc" dict $merged }}
    {{- $_ := set $oidcValues "clients" (concat $givenClients $list) }}

    {{- $found := false }}
    {{- range $container := dig "values" "pod" "initContainers" list $merged }}
      {{- if eq (get $container "name") "oidc-hashes" }}
        {{- $_ := set $container "volumeMounts" (concat (get $container "volumeMounts" | default list) $mounts) }}
        {{- $found = true }}
      {{- end }}
    {{- end }}
    {{- if not $found }}
      {{- fail "oidcClients needs the init container `oidc-hashes` in the values.pod.initContainers of the release `authelia`" }}
    {{- end }}

    {{- $_ := set $resources "fluxHelmReleases" $releases }}
    {{- $_ := set $.Values "resources" $resources }}
  {{- end }}
{{- end }}
