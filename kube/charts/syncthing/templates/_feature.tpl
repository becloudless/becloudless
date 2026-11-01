{{- /*
Prepare the resources of the instance named after the release (see values.yaml). Every resource is the `main` of its kind, so it is
named after the release (`prefixNamesWithRelease`), and the pods are selected by the standard labels of the base chart
(`app.kubernetes.io/instance` is the release, `app.kubernetes.io/component` is `main`) so that instances of the same namespace do not
overlap.

Everything is returned as a default: set `resources.<kind>.<id>...` to override or extend any generated field.

When `relay.host` is set, a sidecar (`files/relay.sh`, the pod restarts when it changes: see the checksum annotations of the base chart) keeps the sync protocol listen address of the instance on that relay: the ID of
the relay is computed from its certificate (`relay.certSecret`) and the token comes from `relay.tokenSecret`.
*/}}
{{- define "syncthing.feature" }}
{{- $rootContext := .rootContext }}
{{- $values := $rootContext.Values }}
{{- $name := $rootContext.Release.Name }}
{{- $user := required "`user` is required" $values.user }}
{{- $domain := required "`app.domain` is required" ($values.app | default dict).domain }}
{{- $host := $values.host | default (printf "%s.syncthing.%s" $user $domain) }}
{{- $tls := printf "tls-%s" $name }}
{{- $relay := $values.relay | default dict }}
{{- $script := $rootContext.Files.Get "files/relay.sh" }}
resources:
{{- if $relay.host }}
  configMaps:
    main:
      data:
        relay.sh: |
{{ $script | indent 10 }}
{{- end }}

  persistentVolumeClaims:
    main:
      storageClassName: {{ $values.storageClassName | quote }}
      resources:
        requests:
          storage: {{ $values.storageSize | quote }}

  deployments:
    main:
      replicas: 1 # one instance is one device
      strategy:
        type: Recreate # the volume is ReadWriteOnce
      template:
        spec:
          securityContext:
            fsGroup: 1000 # the `syncthing` user of the image
          containers:
            syncthing:
              name: syncthing
              image: {{ $values.image | quote }}
              ports:
                http:
                  containerPort: 8384
              env:
                TZ: Europe/Paris
                STNODEFAULTFOLDER: "1" # the folders are added in the UI
              startupProbe:
                httpGet:
                  path: /rest/noauth/health
                  port: 8384
                failureThreshold: 60
              readinessProbe:
                httpGet:
                  path: /rest/noauth/health
                  port: 8384
                timeoutSeconds: 5
              livenessProbe:
                httpGet:
                  path: /rest/noauth/health
                  port: 8384
                periodSeconds: 30
                timeoutSeconds: 10
                failureThreshold: 6
              # started as the user, the entrypoint of the image does not need root then (it only changes the owner of the volume)
              securityContext:
                runAsUser: 1000
                runAsGroup: 1000
                capabilities:
                  drop:
                    all: ALL
              volumeMounts:
                data:
                  name: data
                  mountPath: /var/syncthing
                  subPath: data # the volume has a `lost+found` directory
{{- if $relay.host }}
            relay-config:
              name: relay-config
              image: {{ $values.image | quote }}
              command: [ sh, /scripts/relay.sh ]
              env:
                RELAY_HOST: {{ $relay.host | quote }}
                RELAY_PORT: {{ $relay.port | toString | quote }}
                RELAY_TOKEN:
                  secretKeyRef:
                    name: {{ $relay.tokenSecret.name | quote }}
                    key: {{ $relay.tokenSecret.key | quote }}
              securityContext:
                runAsUser: 1000
                runAsGroup: 1000
                capabilities:
                  drop:
                    all: ALL
              volumeMounts:
                data:
                  name: data
                  mountPath: /var/syncthing
                  subPath: data
                  readOnly: true # only the API key of the instance is read, from its config.xml
                scripts:
                  name: scripts
                  mountPath: /scripts
                  readOnly: true
                relay:
                  name: relay
                  mountPath: /relay
                  readOnly: true
{{- end }}
          volumes:
            data:
              name: data
              persistentVolumeClaim:
                claimName: {{ $name | quote }}
{{- if $relay.host }}
            scripts:
              name: scripts
              configMap:
                name: {{ $name | quote }}
            relay: # the public certificate of the relay only, not its key
              name: relay
              secret:
                secretName: {{ $relay.certSecret.name | quote }}
                items:
                  cert:
                    key: {{ $relay.certSecret.key | quote }}
                    path: tls.crt
{{- end }}

  services:
    main:
      ports:
        http:
          port: 8384

  ciliumNetworkPolicies:
    main:
      endpointSelector:
        matchLabels:
          app.kubernetes.io/instance: {{ $name | quote }}
          app.kubernetes.io/component: main
      ingress:
        gateway: # the web UI
          fromEntities: [ingress, host, remote-node]
          toPorts: [8384]
      egress:
        relay:
          toEndpoints:
            relay:
              matchLabels: {{ $relay.matchLabels | toJson }}
          toPorts: [{{ $relay.port | toString | quote }}]

  certManagerCertificates:
    main:
      secretName: {{ $tls | quote }}
      dnsNames:
        host: {{ $host | quote }}
      issuerRef:
        name: {{ $values.issuer | quote }}
        kind: ClusterIssuer

  listenerSets:
    main:
      parentRef:
        group: gateway.networking.k8s.io
        kind: Gateway
        name: {{ $values.gateway.name | quote }}
        namespace: {{ $values.gateway.namespace | quote }}
      listeners:
        https:
          name: https
          hostname: {{ $host | quote }}
          port: 443
          protocol: HTTPS
          tls:
            mode: Terminate
            certificateRefs:
              tls:
                name: {{ $tls | quote }}
          allowedRoutes:
            namespaces:
              from: Same

  httpRoutes:
    main:
      parentRefs:
        main:
          group: gateway.networking.k8s.io
          kind: ListenerSet
          name: {{ $name | quote }}
      hostnames:
        host: {{ $host | quote }}
      rules:
        root:
          filters:
            authelia:
              type: ExternalAuth
              externalAuth:
                protocol: HTTP
                backendRef:
                  name: authelia
                  namespace: authelia
                  port: 80
                http:
                  path: /api/authz/ext-authz/
                  allowedResponseHeaders: # only the identity headers, not the authz content-type/content-length (a GET with a content-length makes upstreams answer 400)
                    remote-user: remote-user
                    remote-groups: remote-groups
                    remote-name: remote-name
                    remote-email: remote-email
                  allowedHeaders: # what authelia needs to find the session and to redirect to the login page
                    cookie: cookie
                    accept: accept
                    proxy-authorization: proxy-authorization
                    x-forwarded-proto: x-forwarded-proto
                    x-forwarded-for: x-forwarded-for
          backendRefs:
            main:
              name: {{ $name | quote }}
              port: 8384
{{- end }}
