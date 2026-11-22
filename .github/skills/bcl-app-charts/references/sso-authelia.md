# Authelia, lldap, OIDC clients

## Wiring

- Authelia uses the LDAP backend against lldap. A `file` backend gives "user not found" for lldap-only users, and `claims_policies.*.custom_claims.*.attribute` only works with the LDAP backend (the file backend crash-loops with "not a known attribute").
- The bind user `authelia` is created by `lldap-post`; its password is a generated StringSecret `lldap-authelia`, copied into the authelia namespace by external-secrets (SecretStore `lldap` in the authelia namespace with `remoteNamespace: lldap`, ServiceAccount `lldap-reader`, Role/RoleBinding in the lldap namespace created by `lldap-pre`).
- lldap custom attribute names cannot contain `_` (use `immichquota`, not `immich_quota`). Claim names keep their underscores.
- `lldap-post` deletes every user and group that is not declared (`DO_CLEANUP`). Before adopting an existing lldap database, list its users and groups and declare all of them (`config.lldapUsers`, `lldapBootstrap.groups` = union with the chart default), otherwise they are deleted.
- The `lldap-post` Job name is a hash of `lldapBootstrap` + `lldapUsers` only. Job spec changes need a `global.lldapBootstrap.revision` bump (immutable fields).
- Users are declared once in `config.lldapUsers` of the `apps` chart; they reach every app as `global.lldapUsers` through the global-values ConfigMap (lldap-post and syncthing use it).
- JWKS: mounted from the cert-manager secret `authelia-jwks` via `secret.additionalSecrets` (`/secrets/authelia-jwks/tls.{key,crt}`). LDAPS goes through the Let's Encrypt certificate of `lldaps.<domain>`.
- Manual per cluster (authelia namespace): secret `authelia` (`notifier.smtp.password.txt`, `authentication.ldap.password.txt`, `storage.encryption.key`) and `authelia-oidc` (`oidc.client.<name>.value`).
- Authelia needs UDP 123 egress (NTP) and SMTP egress under default deny.
- A value starting with `{{ ... }}` must be quoted in YAML.

## Adding an OIDC client (checklist)

1. Authelia `oidcClients` entry (client id, secret value in `authelia-oidc`, redirect URIs, scopes, auth method, PKCE) and an lldap group `app_<name>` in `lldapBootstrap.groups` (bump `lldapBootstrap.revision`).
2. The app side reads the secret from its own namespace. If it must come from another namespace, use an external-secrets SecretStore with a ServiceAccount and a Role in the source namespace (as authelia does for lldap, seerr for jellyfin).
3. Public clients (`public: true`, no secret, client id = key) exist for CLI tools such as kubelogin.
4. Test the issuer URL without trailing slash (`https://authelia.<domain>`), and the exact redirect URI the app sends.

Per-app OIDC facts:
| App | Redirect / auth specifics |
|-----|---------------------------|
| seafile | `client_secret_basic`, no PKCE. SSO users are regular users only; a local admin `admin@<domain>` has a generated `admin-password`. |
| paperless | PKCE S256, `client_secret_basic`, callback `/accounts/oidc/authelia/login/callback/`, scope `groups`. `PAPERLESS_DISABLE_REGULAR_LOGIN` removes the form and `/admin/login/` redirects to it: no web login for a local admin, only API (basic auth/token). SSO `role_admin` becomes superuser; groups sync by name (create group `app_paperless` in the app by hand). |
| tuwunel | callback `/_matrix/client/unstable/login/sso/callback/<client_id>` (ends with the client id), `claims_policy` id_token, `client_secret_post`, response modes `form_post` + `query`. Users = `preferred_username`; the first SSO user is admin. |
| seerr | upstream preview OIDC image (mutable tag, pinned digest). Config only in `settings.json` (`main.oidcLogin`, `main.applicationUrl`, `oidc.providers[]`). Redirects `/login` and `/profile/settings/linked-accounts`. Default auth `client_secret_post`. |
| sftp | device flow client (`urn:ietf:params:oauth:grant-type:device_code`, confidential, dummy https redirect); the introspection endpoint needs `username` equal to the ssh user. |
| jellyfin | plugin `9p4/jellyfin-plugin-sso` (archived), see [apps.md](./apps.md). |
| kubernetes apiserver | public client `kubernetes`, redirect `http://127.0.0.1:8000` and `:18000` (kubelogin `--oidc-redirect-url-hostname=127.0.0.1`). |

## API server OIDC (serverKube role)

`bcl.role.serverKube.oidc.enable` writes `/etc/kubernetes/authentication-config.yaml` (`apiserver.config.k8s.io/v1`) and the kubeadm `extraArgs`/`extraVolumes`. Usernames and groups are prefixed `oidc:`; `oidc:role_admin` maps to cluster-admin in `app-kube`.
- The CA is inlined from `pkgs.cacert` `ca-no-trust-rules-bundle.crt`: the host `/etc/ssl/certs` symlinks are broken inside the kubeadm apiserver pod, and `security.pki.caBundle` has `TRUSTED CERTIFICATE` blocks that Go ignores.
- The file is read at apiserver start only: a change needs an apiserver restart.
- The container kubelet node role is not covered.

## Forward auth

Cilium ingress has no forward auth. Use the Gateway API `ExternalAuth` HTTPRoute filter, see [gateway-api.md](./gateway-api.md). Authelia side: `server.endpoints.authz.ext-authz.implementation: ExtAuthz` and a ReferenceGrant listing every consumer namespace.

Per-user rules (syncthing UIs): `domain_regex ^(?P<User>[a-z0-9-]+)\.syncthing\.<quoted domain>` with policy `two_factor` and no `subject`: the named group `User` is itself compared to the username. `subject: user:{user}` is not a placeholder (literal user `{user}`, always 403 `Access ... is forbidden to user '<name>'` in the Authelia log).

## Startup self-configuration pattern

Apps without declarative config (jellyfin wizard, seerr settings) use an init container or sidecar with a script in a ConfigMap that completes the setup through the app's API, idempotently, and loops (hourly) to revert UI drift. Verify against a mock server when no real instance is available and say so.
