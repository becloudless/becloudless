# Remaining simplifications of the app charts

Done so far (values of `app-*`, code lines without comments and blanks: 8640 to 6241, -28%):

- `app.loader.expose`: public exposure (certificate, listener, route, release `<id>-integration`);
- `app.loader.oidc` and `oidcClients` of `app-authelia`: OIDC client creation and link;
- the default chart of an app HelmRelease is the base chart;
- the probe shorthand (`probe:`);
- the comments that state what is true for every app.

The counts are measured on the `app-*/values.yaml` files, the gains are estimates (lines of values).
Each step must keep the golden `ci/ci-result.yaml` of the charts identical (the exceptions are said).

| # | Simplification | Gain |
|---|---|---|
| 1 | `dependsOn` inferred from the resources | about 150 lines |
| 2 | Names from the keys, `volumeMounts` and PVC volume shorthands | 150 to 200 lines |
| 3 | Port declared once, default Service from the container ports | 60 to 120 lines |
| 4 | Container hardening defaults still repeated | about 100 lines |
| 5 | Gateway ingress policy generated from `expose` | about 76 lines |
| 6 | Named egress peers | 100 to 150 lines |
| 7 | Volume driven defaults | about 50 lines |
| 8 | `expose.port` inferred | about 20 lines |
| 9 | Name from the key for `expose` and `oidc` | small |
| 10 | Renovate markers in the renovate configuration | 17 lines |
| 11 | Per app headers moved to the website docs | about 250 comment lines |
| 12 | Embedded scripts and CSS moved to `files/` | readability |
| 13 | `postgresql` and `valkey` features | about 190 lines |

The gains overlap (1 with 13, 3 with 8, 5 and 6 with 13): the total of 1 to 9 and 13 is about 700 lines (11% of the 6241 code lines left).

## 1. `dependsOn` inferred from the resources (about 150 lines)

98 `namespace:` lines in 22 charts. A release depends on a controller when its `resources` use what it serves:

| Resource | Dependency | Today |
|---|---|---|
| `stringSecrets` | `app-secret-generator` | 14 lines in 10 charts |
| `externalSecrets`, `secretStores` | `app-external-secrets` | 8 lines in 8 charts |
| `certManagerCertificates` | `app-cert-manager` | 12 lines in 9 charts |
| a `longhorn-*` storage class | `app-longhorn` | 11 lines in 11 charts |
| the `<id>-pre` release of the app | `ref:<id>-pre` | 17 lines in 15 charts |

- In `app/templates/_mergeRelease.tpl`, which already completes `dependsOn`.
- Garage uses `volumeClaimTemplates`: match the class name anywhere in the release.
- The golden may change the order of the `dependsOn` lists, not their content.

## 2. Names from the keys (83 lines in 19 charts, plus shorthands)

`name: X` directly under the key `X:` (containers, initContainers, volumes, volumeMounts), for example in `app-tuwunel`:

```yaml
containers:
  tuwunel:
    name: tuwunel
volumeMounts:
  data:
    name: data
    mountPath: /var/lib/tuwunel
```

- Add these paths with `keyField: name` to the `itemFields` of the base renderer
  (`base/templates/resources/mutations/itemFields/itemFields.go` and its generated paths). Only the `name:` lines change.
- `volumeMounts` shorthand `data: /var/lib/tuwunel` (37 `mountPath` lines in 13 charts), with the `listShorthands` style expansion.
- PVC volume shorthand: 6 `persistentVolumeClaim: {claimName: ref:...}` become `data: {pvc: tuwunel-data}`.

## 3. Port declared once, default Service (60 to 120 lines)

18 `containerPort` lines in 14 charts, 16 `services:` blocks in 14 charts (52 `port:` lines in 23 charts) repeat the same number, and
`expose.port` a third time.

- Generate the Service named after the deployment from its container ports when none is declared (the `portMaps` mutation already turns
  port maps into lists).
- The `toPorts` of the ingress policy follow (see 5).

## 4. Container hardening defaults still repeated (about 100 lines)

`base/values.yaml` already defaults `runAsNonRoot`, `seccompProfile`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, the
`/tmp` volume and the probe timings. Still repeated:

- `capabilities: {drop: {all: ALL}}`: 19 blocks of 3 lines in 13 charts, default in `defaults.container.securityContext`. The containers that
  add capabilities override it (cilium, longhorn, seafile);
- `runAsUser` and `runAsGroup: 1000` (16 each in 11 charts): default to 1000. Exceptions: firefox-sync (10001), mailu (0), seafile mariadb
  (999), element (fsGroup 101).

Opt-out for the images that must run as root, as for `readOnlyRootFilesystem` today.

## 5. Gateway ingress policy from `expose` (about 76 lines)

The same block in 19 policies in 16 charts (4 lines):

```yaml
ingress:
  gateway:
    fromEntities: [ingress, host, remote-node]
    toPorts: [3000]
```

`expose` knows the port. Add a selector option (`ref:<id>` by default, the deployment of the same name) and generate the ingress rule of a
policy `<id>-gateway`. Cilium policies are additive, so the policy of the app keeps its other rules.

## 6. Named egress peers (100 to 150 lines)

Library table expanded when the value is `{}`:

| Key | Expands to | Today |
|---|---|---|
| `kube-apiserver` | `toEntities: [kube-apiserver]` | 37 lines in 14 charts |
| `gateway` | `toEntities: [ingress]`, 443 | 9 blocks of 3 lines |
| `authelia` | FQDN `authelia.<domain>`, 443 | 7 blocks of 4 lines, the `oidc` apps |

`oidc` can add the authelia and gateway egress for the selector of the app itself.

## 7. Volume driven defaults (about 50 lines)

- `strategy: {type: Recreate}`: 6 deployments in 5 charts. The `recreateStrategy` mutation only removes the `rollingUpdate`: choose
  `Recreate` when the pod mounts a ReadWriteOnce PVC and sets no strategy;
- `fsGroup`: 11 in 8 charts, the group of the user of the container (see 4);
- `storageClassName: longhorn-*`: 11 in 8 charts. Default `longhorn-files` in `defaults.resources.persistentVolumeClaims`, set only
  `longhorn-db`.

## 8. `expose.port` inferred (about 20 lines)

After 3: the port of the only Service port of the target (or of the only container port) when `port` is not set.

## 9. Name from the key for `expose` and `oidc` (small)

`endpointSelector: ref:x` (15) and the `hostname` of `expose` repeat the id of the entry. Default `ref:<id>` and `<id>`.

## 10. Renovate markers (17 lines)

17 `# renovate: versioning=loose` comments in 12 charts: one package rule in the renovate configuration (`renovate.json5`) matching the
images of the app values, less noise on every image line.

## 11. Per app headers to the website (about 250 comment lines)

The headers of tuwunel, seerr, paperless, garage, seafile, jellyfin, prometheus, firefox-sync, immich and mailu are user documentation
(how to log in, what is not configured, how to use the CLI...). Move them to one page per app in
`../../website/content/docs/kubernetes/` and keep two lines in the values (what it is, where the doc is). It moves the text, it does not
remove it.

## 12. Scripts and CSS to `files/` (readability)

Embedded in the values today: jellyfin `configure.js`, the seerr configure and admin scripts, the lldap `bootstrap.sh`, the garage-layout
script, the homer CSS, the landing HTML, the seafile login override. Same total size, but the values stay readable, the files get their
syntax highlighting and can be tested. The `app` chart reads them with `.Files.Get`.

## 13. `postgresql` and `valkey` features (about 190 lines)

The same release repeats in 7 charts for postgresql (authelia, lldap, forgejo, paperless, immich, seerr, firefox-sync) and in 4 for
valkey (authelia, immich, paperless, seafile). A postgresql block is about 14 lines plus a 5 lines egress policy:

- the `clients` selector;
- `dependsOn` `app-cert-manager`, `app-cnpg`, `app-longhorn`;
- `chart: ./kube/charts/postgresql`;
- the egress to `cnpg.io/cluster: <id>-postgresql` on 5432.

Valkey is the same with `app-secret-generator` and 6379. Target:

```yaml
postgresql:
  forgejo: {}
  paperless: {storageSize: 5Gi}
valkey:
  paperless: {}
```

- New `app/templates/features/_postgresql.tpl` and `_valkey.tpl`, called by `app.loader.init` after `oidc`; schema in
  `app/schema/values.schema.json`, cases in `app/ci/ci-values.yaml`, section in
  `../../website/content/docs/kubernetes/app-charts.md`.
- The release names stay `<id>-postgresql` and `<id>-valkey` (`ref:forgejo-postgresql`, `forgejo-postgresql-rw`, the `-app` secret).
- The client label convention differs (`app.kubernetes.io/name: forgejo`, or `instance` and `component` in paperless, lldap, firefox-sync,
  seafile): a `clients` option is needed.

## Order

1. 2 (names from the keys), the smallest and safest.
2. 13 (`postgresql` and `valkey`).
3. 5 and 6 (network policy shorthands).
4. 1 (`dependsOn` inferred).
5. 4 and 7 (defaults), the most exceptions.
6. 3 and 8 (Service and port).
7. 9 and 10, then 11 and 12 (docs and files).

2, 3, 5, 6, 8, 9, 12 and 13 keep the goldens identical; 1 may reorder `dependsOn`; 4 and 7 keep them identical once the exceptions are
explicit; 10 and 11 change no rendered output.
