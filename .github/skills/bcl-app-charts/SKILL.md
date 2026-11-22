---
name: bcl-app-charts
description: "Use when: working on specific bcl app charts or their integration: Authelia/lldap SSO and OIDC clients (jellyfin, seerr, seafile, paperless, tuwunel/element, sftp, kubernetes apiserver), Gateway API exposure (shared Gateway, ListenerSet, HTTPRoute, TLSRoute, TCPRoute, ExternalAuth forward auth, ReferenceGrant, cert-manager gatewayAPI solver), CloudNativePG + cert-manager CA deadlock, valkey, syncthing relay, mailu, firefox-sync, csi-rclone, Cilium in its own namespace, HelmRelease stuck after an upgrade."
---

# bcl app charts: SSO, exposure, per-app notes

Read [bcl-kube-charts](../bcl-kube-charts/SKILL.md) for chart mechanics and [bcl-kube-operations](../bcl-kube-operations/SKILL.md) before touching a live cluster. Nothing here is applied automatically: charts are published by the maintainer and Flux follows the tracked branch.

Details:
- [references/sso-authelia.md](./references/sso-authelia.md): lldap, Authelia, OIDC clients, apiserver OIDC.
- [references/gateway-api.md](./references/gateway-api.md): Gateway, ListenerSet, routes, forward auth, cert-manager, namespaces.
- [references/apps.md](./references/apps.md): per-app facts (syncthing, seafile, paperless, tuwunel, sftp, jellyfin, seerr, valkey, mailu, ...).

## Rules that apply to every app chart

- Build and read the golden diff as described in `bcl-kube-charts`. Charts are verified by `bcl k chart build` and, when possible, by running the real image in docker (rootless, read-only rootfs, dropped caps). State clearly what was only built and what was run.
- Env vars: the base chart sorts `env` by name, and `$(VAR)` only sees variables defined before it. Name helper variables so they sort first (`BROKER_PASSWORD`, `DB_PASSWORD`, `OIDC_*` before `APP_*`).
- `enableServiceLinks: false` whenever a Service name can collide with an app option (a Service `tuwunel` injects `TUWUNEL_PORT=tcp://...`, seafile has the same issue).
- `checkRequiredValues` treats any `null` in `values.yaml` as required. Use `""` or `{}` for optional keys.
- A new `app-*` chart needs `templates/loader.yaml` and `ci/ci-values.yaml` copied from another app chart, a registry entry in the `apps` values, and a docs line.
- Image tags: pin by digest when the tag is mutable. A placeholder tag (`0.0.0`) is fine until CI publishes the image: say so.
- Secrets that cannot be generated stay manual per cluster: document the secret name and keys at the top of `values.yaml`.
- Chart-managed objects patched live are reverted by Flux/Helm within minutes. A hand-created object that the chart also renders breaks the next upgrade: delete it once the chart publishes it.
- A HelmRelease adopted from a legacy kustomize apply may keep stale fields in `spec.values` that Helm's three-way merge never removes (e.g. an old `additionalSecrets` entry pointing to a missing secret keeps the pod in `Init`). Compare `kubectl get hr -o yaml` with the golden and JSON-patch `remove` the stale key.
- Flux does not re-run a HelmRelease when only its `valuesFrom` ConfigMap changes unless the ConfigMap has the label `reconcile.fluxcd.io/watch: Enabled`. Otherwise run `flux reconcile hr <name> -n <ns>`.
- An app with a startup check to an external host (SMTP, NTP, OIDC issuer) needs an explicit egress policy: the failure only shows after the pods restart (old pods predate the default-deny policy).

## CloudNativePG with cert-manager certificates

Apps using user-managed certs have four objects in `kube/apps/<app>/postgresql/`: a CA Certificate (`isCA`, self-signed issuer), server, app and replication Certificates. Symptom of the deadlock: Cluster status `generating streaming replication client certificate: failed to verify certificate: x509: certificate signed by unknown authority`, new instance pods never get a PVC, or a stale `-join` Job shows `Complete` against a deleted PVC.

Cause: the CA secret was deleted and recreated (new CA key), the leaves are signed by the old key and CNPG only checks expiry and DNS names.

Fix without downtime for the running primary:
1. `openssl verify -CAfile ca.crt leaf.crt` to confirm.
2. `kubectl -n <ns> delete secret <app>-postgresql-tls <app>-postgresql-app-tls <app>-postgresql-replication-tls` (never the `*-ca` secret). cert-manager reissues them within seconds.
3. If a stale join Job exists: delete `job <cluster>-<N>-join` and `pod <cluster>-<N>`.

The CA certificates carry `privateKey.rotationPolicy: Never`. Rule: never delete a `*-postgresql-ca` secret.

## HelmRelease upgrade stuck: checklist

1. `kubectl describe pod`: a missing secret usually means a stale value (above) or a secret that the chart's `-pre` release should create.
2. Process crashes at startup on an external dependency: default-deny egress missing (see network policy rules in `bcl-kube-charts`). Test from the pod with the exact host and port the app logs.
3. When an authenticated mail client times out, check each hop: the front proxies authenticated submission (465/587) to the backend on port 10025, which needs its own egress and ingress rules in addition to port 25.
4. `Unable to create required cluster objects` on a CNPG Cluster: the certificate deadlock above.
5. Changing `targetNamespace` of an existing release makes helm-controller reinstall: risky on a live cluster.
6. A `dependsOn` on an app that is not enabled in the group blocks forever (the registry does not filter).
