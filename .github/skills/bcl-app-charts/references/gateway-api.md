# Gateway API exposure (Cilium)

## Model

- Cilium ingress is disabled. A single Gateway `shared` (namespace `cilium`, created by the `cilium-post` release) owns the load balancer IP. Gateway API CRDs are the experimental channel (needed for `ExternalAuth`), installed by the `app-gateway-api` chart.
- Per app: a Certificate (secret named `tls-<app>-gateway`, to avoid a clash with ingress-shim secrets), a ListenerSet, and an HTTPRoute/TLSRoute/TCPRoute whose `parentRefs` has kind `ListenerSet` (+ `sectionName`).
- The Gateway itself only has the port 80 listener; 443 listeners come from the ListenerSets.
- After the Gateway API CRDs are first installed, restart `cilium-operator`. An old ingress Service must be gone before the Gateway can take its pinned IP. After enabling any Envoy-based feature, restart the cilium agents (config drift `enable-envoy-config=false` leaves the LB IP refusing connections).
- Moving Cilium from `kube-system` to its own namespace: the Gateway moves with it, so every `parentRef` namespace changes (app `_expose.tpl`, kube, syncthing, mailu, cert-manager, chart defaults). For goldens that drifted on image versions, patch only the namespace line (perl on `name: shared` / `namespace:`) instead of a full regeneration. Live cutover risks: old and new agents/operators fight (host ports, leader election leases), pinned LB IP (delete the old Gateway first), Flux pulls from git so push first, suspend the old HelmReleases.

## Routes and listeners

| Need | Resource | Notes |
|------|----------|-------|
| HTTPS app | ListenerSet `https` (Terminate) + HTTPRoute | cert from cert-manager |
| TLS passthrough (e.g. LDAPS, SSH over TLS) | ListenerSet listener `tls` mode Passthrough + TLSRoute | HTTPS and Passthrough on the same port conflict only when hostnames overlap (a wildcard passthrough blocks every HTTPS host under it; exact passthrough hosts coexist) |
| Raw TCP (syncthing relay) | ListenerSet TCP listener + TCPRoute | TCPRoute is served on the Gateway LB service without Envoy; a TCP listener owns the whole port. TLSRoute needs hostnames (SNI), BEP dialers send none |
| Forward auth | HTTPRoute filter `ExternalAuth` -> authelia `/api/authz/ext-authz/` | needs ReferenceGrant |

- Cilium cannot terminate non-HTTP TLS (TLSRoute `mode: Terminate` is rejected). Use a TLS terminator (nginx sidecar) behind a Passthrough TLSRoute.
- ExternalAuth needs a ReferenceGrant per consumer namespace in the authelia release (`app-authelia` values). Without it the route has `RefNotPermitted` and Envoy returns 500 with an empty body: `kubectl -n <ns> get httproute -o yaml | grep -A3 ResolvedRefs`.
- A public IP of the cluster's own Gateway seen from inside a pod is not entity `ingress` for Cilium: policies need `toFQDNs` for it, plus an `ingress` entity rule.
- A plain Kubernetes NetworkPolicy selecting a pod (Flux `allow-webhooks`) denies Gateway Envoy traffic (entity `ingress`, not a pod): add a CiliumNetworkPolicy with `fromEntities [ingress, host, remote-node]`.
- Old HTTP/1.0 upstream proxies (nginx `proxy_pass` default) get `426 Upgrade Required` from Envoy: set `proxy_http_version 1.1`. Test with `curl --http1.0` vs `--http1.1`.
- ACME HTTP-01 for ingress-shim certificates still needs a path public:80 -> Gateway :80 over HTTP/1.1.

## cert-manager

- `config.gatewayAPI.enabled` and the ClusterIssuer solver `http01.gatewayHTTPRoute.parentRefs` pointing to the Gateway `shared` listener `http` (listener `allowedRoutes: All`). cert-manager `dependsOn` gateway-api.
- A Certificate for a listener hostname; the Certificate must exist before the ListenerSet can be Accepted.
- Flux webhook resources are `enabled: false` in `app-flux` for the minimal group (no CRDs); enable them in the cluster values together with `dependsOn` cert-manager and gateway-api.

## Namespaces

`app-*` charts do not ship Namespace resources (uninstalling a failed release deleted a namespace stuck on a snapshot finalizer). `apps.<name>.targetNamespace` in the registry makes the template set `releaseName: app-<name>`, `storageNamespace: bcl`, `install.createNamespace`; the CLI bootstrap adds a Namespace document. `Release.Namespace` is then the app namespace, so GitRepository refs use the literal `bcl`.

## Retiring a legacy path safely

Before removing an access path (an old proxy, an old ingress controller), check what the maintainer's own tooling uses (`~/.ssh/config`, git remotes, kubeconfig server). A "known loss" that breaks the push channel must not be pushed. Retiring an old Kustomization with `prune: true`: patch `spec.prune=false`, suspend, remove finalizers, then delete; the same-name HelmRelease is taken over by the new one as an in-place upgrade (delete the old Deployment first when the selector differs).
