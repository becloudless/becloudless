{{- /*
The `expose` values: the public exposure of an app by the Cilium Gateway `shared` (kube-system), TLS terminated by the Gateway. The key
is the id of an exposed hostname, the value its options:
  - `hostname`: the subdomain of `app.domain` (the id by default). A value with a dot is used as it is (ex: `"{{ .Values.app.domain }}"`
    for the apex).
  - `service`: the name of the Service that gets the requests (`ref:<id>` by default), `port` its port (not set by default).
  - `auth`: `none` (default) or `authelia`, the forward auth of Authelia. The ReferenceGrant to the authelia service is in app-authelia.
  - `timeouts`: the timeouts of the route (`{request: 0s}` for the uploads, the downloads and the streams, that can be long).
  - `release`: the hostnames of a same release are exposed together (the id by default). The release is `<release>-integration`: a
    release that waits for the certificates (cert-manager) and the Gateway API CRDs, applied once the app is deployed and not
    waited for.
  - `dependsOn`: what the release waits for (`[ref:<release>]` by default), the entries of the hostnames of the release are added.
  - `enabled`: `false` disables the release (a cluster enables it with the `enabled` of the release).
It generates the certificate `<id>-gateway` (secret `tls-<id>-gateway`), a listener `<id>` in the ListenerSet `<release>`, and the HTTPRoute
`<id>`. A release with the same name in `resources.fluxHelmReleases` is merged with the generated one and wins, to add what the shorthand
does not do (a TLS passthrough listener, a ReferenceGrant...).
*/}}
{{- define "app.loader.expose" }}
  {{- $expose := $.Values.expose }}
  {{- if $expose }}
    {{- if not (kindIs "map" $expose) }}
      {{- fail "expose must be a map, keyed by the id of the exposed hostname" }}
    {{- end }}
    {{- $domain := "{{ .Values.app.domain }}" }}
    {{- $allowed := list "release" "hostname" "service" "port" "auth" "timeouts" "dependsOn" "enabled" }}
    {{- $resources := $.Values.resources | default dict }}
    {{- $releases := $resources.fluxHelmReleases | default dict }}

    {{- $groups := dict }}
    {{- range $id := keys $expose | sortAlpha }}
      {{- $entry := get $expose $id | default dict }}
      {{- range $key := keys $entry }}
        {{- if not (has $key $allowed) }}
          {{- fail (printf "expose.%s.%s is not an option (%s)" $id $key (join ", " $allowed)) }}
        {{- end }}
      {{- end }}
      {{- $release := $entry.release | default $id }}
      {{- $group := get $groups $release | default dict }}
      {{- $_ := set $group $id $entry }}
      {{- $_ := set $groups $release $group }}
    {{- end }}

    {{- range $release, $group := $groups }}
      {{- $certificates := dict }}
      {{- $listeners := dict }}
      {{- $routes := dict }}
      {{- $dependsOn := list }}
      {{- $enabled := true }}
      {{- range $id := keys $group | sortAlpha }}
        {{- $entry := get $group $id }}
        {{- $hostname := $entry.hostname | default $id }}
        {{- if not (contains "." $hostname) }}
          {{- $hostname = printf "%s.%s" $hostname $domain }}
        {{- end }}
        {{- $certificate := printf "%s-gateway" $id }}
        {{- $_ := set $certificates $certificate (dict
              "secretName" (printf "tls-%s" $certificate)
              "dnsNames" (dict $id $hostname)
              "issuerRef" (dict "name" "letsencrypt-prod" "kind" "ClusterIssuer")) }}
        {{- $_ := set $listeners $id (dict
              "name" $id
              "hostname" $hostname
              "port" 443
              "protocol" "HTTPS"
              "tls" (dict "mode" "Terminate" "certificateRefs" (dict "tls" (dict "name" (printf "ref:%s" $certificate))))
              "allowedRoutes" (dict "namespaces" (dict "from" "Same"))) }}

        {{- $backend := dict "name" ($entry.service | default (printf "ref:%s" $id)) }}
        {{- if hasKey $entry "port" }}
          {{- $_ := set $backend "port" $entry.port }}
        {{- end }}
        {{- $rule := dict "backendRefs" (dict "backend" $backend) }}
        {{- if $entry.timeouts }}
          {{- $_ := set $rule "timeouts" $entry.timeouts }}
        {{- end }}
        {{- $auth := $entry.auth | default "none" }}
        {{- if eq $auth "authelia" }}
          {{- $_ := set $rule "filters" (dict "authelia" (include "app.loader.exposeAuthelia" $ | fromYaml)) }}
        {{- else if ne $auth "none" }}
          {{- fail (printf "expose.%s.auth is %q, not none or authelia" $id $auth) }}
        {{- end }}
        {{- $_ := set $routes $id (dict
              "parentRefs" (dict $id (dict "group" "gateway.networking.k8s.io" "kind" "ListenerSet" "name" $release "sectionName" $id))
              "hostnames" (dict $id $hostname)
              "rules" (dict "root" $rule)) }}

        {{- if hasKey $entry "dependsOn" }}
          {{- range $dependency := $entry.dependsOn }}
            {{- if not (has $dependency $dependsOn) }}
              {{- $dependsOn = append $dependsOn $dependency }}
            {{- end }}
          {{- end }}
        {{- else if not (has (printf "ref:%s" $release) $dependsOn) }}
          {{- $dependsOn = append $dependsOn (printf "ref:%s" $release) }}
        {{- end }}
        {{- if and (hasKey $entry "enabled") (eq (toString $entry.enabled) "false") }}
          {{- $enabled = false }}
        {{- end }}
      {{- end }}

      {{- $dependsOn = append $dependsOn (dict "name" "app-cert-manager" "namespace" "cert-manager") }}
      {{- $dependsOn = append $dependsOn (dict "name" "app-gateway-api" "namespace" "gateway-api") }}
      {{- $generated := dict
            "install" (dict "disableWait" true)
            "upgrade" (dict "disableWait" true)
            "dependsOn" $dependsOn
            "values" (dict "resources" (dict
              "certManagerCertificates" $certificates
              "listenerSets" (dict $release (dict
                "parentRef" (dict "group" "gateway.networking.k8s.io" "kind" "Gateway" "name" "shared" "namespace" "kube-system")
                "listeners" $listeners))
              "httpRoutes" $routes)) }}
      {{- if not $enabled }}
        {{- $_ := set $generated "enabled" false }}
      {{- end }}
      {{- $name := printf "%s-integration" $release }}
      {{- $given := get $releases $name }}
      {{- if kindIs "map" $given }}
        {{- $generated = (include "base.lib.mergeDefaults" (dict "dst" $given "src" $generated) | fromYaml).value }}
      {{- end }}
      {{- $_ := set $releases $name $generated }}
    {{- end }}

    {{- $_ := set $resources "fluxHelmReleases" $releases }}
    {{- $_ := set $.Values "resources" $resources }}
  {{- end }}
{{- end }}

{{- /* The forward auth of Authelia, the `ExternalAuth` filter of an HTTPRoute. */}}
{{- define "app.loader.exposeAuthelia" }}
type: ExternalAuth
externalAuth:
  protocol: HTTP
  backendRef:
    name: authelia
    namespace: authelia
    port: 80
  http:
    path: /api/authz/ext-authz/
    # only the identity headers, not the authz content-type/content-length (a GET with a content-length makes upstreams answer 400)
    allowedResponseHeaders:
      remote-user: remote-user
      remote-groups: remote-groups
      remote-name: remote-name
      remote-email: remote-email
    # what authelia needs to find the session and to redirect to the login page
    allowedHeaders:
      cookie: cookie
      accept: accept
      proxy-authorization: proxy-authorization
      x-forwarded-proto: x-forwarded-proto
      x-forwarded-for: x-forwarded-for
{{- end }}
