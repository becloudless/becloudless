# demo-resources

Example chart showing how to consume the [`base-resources`](../base-resources)
library chart to declare plain Kubernetes resources (and a few common CRDs)
purely from `values.yaml`, without writing any templates yourself.

## How it works

- `Chart.yaml` declares `base-resources` as a local file dependency.
- `templates/loader.yaml` is the only template needed; it just does:
  ```yaml
  {{- include "base-resources.loader.all" . }}
  ```
- `values.yaml` declares resources under `resources.<kind>.<id>`, where
  `<kind>` is the plural camelCase Kubernetes kind (`deployments`,
  `configMaps`, `services`, ...) and `<id>` is an arbitrary key. The
  resulting object's name is `<release name>-<id>`, or just `<release name>`
  when `<id>` is `main`.
- `defaults.resources.<kind>` is deep-merged under every instance of that
  kind, handy for labels/annotations shared across all resources of a kind.
- `defaults.metadata.labels`/`defaults.metadata.annotations` are deep-merged
  across every resource of every kind, below `defaults.resources.<kind>` and
  the resource's own `labels`/`annotations` in precedence - handy for
  labels/annotations shared across the whole chart (e.g. `app.kubernetes.io/part-of`).
- Every resource supports `nameOverride`, `fullNameOverride`, `namespace`,
  `labels`, `annotations` and `enabled` (defaults to `true`), on top of that
  kind's normal spec fields.

See `base-resources`'s own [`ci/`](../base-resources/ci) directory for a
values.yaml example per supported resource kind, and its generated
`values.schema.json` for the full set of kinds and fields.

## Usage

```sh
helm dependency update .
helm template demo .
```
